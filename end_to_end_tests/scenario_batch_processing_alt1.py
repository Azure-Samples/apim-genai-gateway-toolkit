from datetime import datetime, timedelta, UTC
import logging

import asciichartpy as asciichart
from azure.identity import DefaultAzureCredential
from locust import HttpUser, LoadTestShape, task, constant, events

from common.log_analytics import (
    GroupDefinition,
    QueryProcessor,
)
from common.latency import (
    set_simulator_chat_completions_latency,
    report_request_metric,
)
from common.config import (
    apim_subscription_one_key,
    simulator_endpoint_payg1,
    tenant_id,
    subscription_id,
    resource_group_name,
    app_insights_connection_string,
    log_analytics_workspace_id,
    log_analytics_workspace_name,
)

test_start_time = None
deployment_name = "embedding100k"

#
# model deployments:
#
# embedding
#  - 10k TPM
#  - 60 RPM (1 RPS)
#
# embedding100k
#  - 100k TPM
#  - 600 RPM (10 RPS)


class StagesShape(LoadTestShape):
    """
    Custom LoadTestShape to simulate a spike in traffic part way through the test
    """

    # See https://docs.locust.io/en/stable/custom-load-shape.html
    stages = [
        # {"duration": 120, "users": 2, "spawn_rate": 0.1},
        # {"duration": 300, "users": 6, "spawn_rate": 1},
        {"duration": 60, "users": 4, "spawn_rate": 1},
        {"duration": 120, "users": 8, "spawn_rate": 1},
        {"duration": 180, "users": 12, "spawn_rate": 1},
        {"duration": 240, "users": 16, "spawn_rate": 1},
        {"duration": 300, "users": 20, "spawn_rate": 1},
    ]

    def tick(self):
        run_time = self.get_run_time()

        for stage in self.stages:
            if run_time < stage["duration"]:
                return (stage["users"], stage["spawn_rate"])

        return None


# use short input text to validate request-based limiting, longer text to validate token-based limiting
# TODO - split tests!
# input_text = "This is some text to generate embeddings for
input_text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Habitant morbi tristique senectus et netus et malesuada. Bibendum neque egestas congue quisque egestas diam. Rutrum quisque non tellus orci ac auctor augue. Diam in arcu cursus euismod quis. Euismod elementum nisi quis eleifend quam adipiscing. Posuere lorem ipsum dolor sit amet consectetur adipiscing elit duis. Pretium vulputate sapien nec sagittis aliquam malesuada bibendum arcu. Adipiscing diam donec adipiscing tristique risus nec. Nec ultrices dui sapien eget mi proin. Odio facilisis mauris sit amet. Eget aliquet nibh praesent tristique magna. Malesuada nunc vel risus commodo viverra maecenas accumsan lacus vel. Maecenas volutpat blandit aliquam etiam erat velit scelerisque in dictum. Venenatis tellus in metus vulputate. Aliquet enim tortor at auctor urna nunc id cursus metus. Sed velit dignissim sodales ut eu sem integer vitae justo."
# input_text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Habitant morbi tristique senectus et netus et malesuada. Bibendum neque egestas congue quisque egestas diam. Rutrum quisque non tellus orci ac auctor augue. Diam in arcu cursus euismod quis. Euismod elementum nisi quis eleifend quam adipiscing. Posuere lorem ipsum dolor sit amet consectetur adipiscing elit duis. Pretium vulputate sapien nec sagittis aliquam malesuada bibendum arcu. Adipiscing diam donec adipiscing tristique risus nec. Nec ultrices dui sapien eget mi proin. Odio facilisis mauris sit amet. Eget aliquet nibh praesent tristique magna. Malesuada nunc vel risus commodo viverra maecenas accumsan lacus vel. Maecenas volutpat blandit aliquam etiam erat velit scelerisque in dictum. Venenatis tellus in metus vulputate. Aliquet enim tortor at auctor urna nunc id cursus metus. Sed velit dignissim sodales ut eu sem integer vitae justo. Posuere lorem ipsum dolor sit amet consectetur adipiscing elit. Egestas sed tempus urna et. Vestibulum rhoncus est pellentesque elit ullamcorper dignissim cras tincidunt. Quis viverra nibh cras pulvinar mattis nunc sed. Morbi tempus iaculis urna id. Nisl purus in mollis nunc. Suspendisse potenti nullam ac tortor vitae purus faucibus ornare suspendisse. Nunc mi ipsum faucibus vitae aliquet nec ullamcorper. Semper auctor neque vitae tempus. Euismod lacinia at quis risus sed vulputate. Vitae et leo duis ut diam quam nulla porttitor massa. Sed viverra tellus in hac habitasse platea dictumst. Euismod quis viverra nibh cras pulvinar. Vivamus arcu felis bibendum ut tristique. Lectus proin nibh nisl condimentum id venenatis a. Quis hendrerit dolor magna eget. Neque ornare aenean euismod elementum nisi quis eleifend. Ipsum a arcu cursus vitae congue mauris. Consequat mauris nunc congue nisi vitae suscipit. Libero volutpat sed cras ornare. Malesuada proin libero nunc consequat interdum varius sit amet. Dis parturient montes nascetur ridiculus mus mauris. Penatibus et magnis dis parturient. Nibh ipsum consequat nisl vel. Dictum at tempor commodo ullamcorper a lacus vestibulum. Euismod nisi porta lorem mollis aliquam ut. Dignissim diam quis enim lobortis scelerisque fermentum dui faucibus. Pellentesque sit amet porttitor eget dolor morbi. Pharetra sit amet aliquam id diam maecenas. Volutpat lacus laoreet non curabitur gravida arcu ac tortor dignissim. Sodales ut etiam sit amet nisl purus in mollis. Semper risus in hendrerit gravida rutrum. Natoque penatibus et magnis dis parturient. Ornare quam viverra orci sagittis eu volutpat odio. Tristique sollicitudin nibh sit amet commodo nulla facilisi. Laoreet suspendisse interdum consectetur libero id. Lectus urna duis convallis convallis. Bibendum ut tristique et egestas quis ipsum suspendisse. Sollicitudin aliquam ultrices sagittis orci a scelerisque purus semper eget. Placerat vestibulum lectus mauris ultrices eros in cursus. Sed turpis tincidunt id aliquet. Tristique senectus et netus et malesuada fames. Ut placerat orci nulla pellentesque dignissim enim sit amet venenatis. Vitae proin sagittis nisl rhoncus mattis. Diam donec adipiscing tristique risus nec. Venenatis tellus in metus vulputate eu scelerisque felis. Dis parturient montes nascetur ridiculus mus mauris vitae. Scelerisque purus semper eget duis at tellus. Vel elit scelerisque mauris pellentesque pulvinar pellentesque. Dictum sit amet justo donec. Vestibulum rhoncus est pellentesque elit ullamcorper dignissim cras tincidunt lobortis. Tristique et egestas quis ipsum suspendisse ultrices gravida dictum fusce. Facilisi cras fermentum odio eu feugiat pretium nibh ipsum. Congue mauris rhoncus aenean vel elit scelerisque mauris pellentesque. Sed felis eget velit aliquet sagittis id. Fermentum leo vel orci porta. Lectus vestibulum mattis ullamcorper velit sed ullamcorper. Vitae proin sagittis nisl rhoncus. Habitant morbi tristique senectus et netus. Nisl vel pretium lectus quam id leo in vitae turpis."


class EmbeddingUser(HttpUser):
    """
    EmbeddingUser makes calls to the OpenAI Embeddings endpoint to show traffic via APIM
    """

    wait_time = constant(1)  # wait 1 second between requests

    @task
    def get_completion(self):
        url = f"openai/deployments/{deployment_name}/embeddings?api-version=2023-05-15"
        payload = {
            "input": input_text,
            "model": "embedding",
        }
        try:
            self.client.post(
                url,
                json=payload,
                headers={
                    "ocp-apim-subscription-key": apim_subscription_one_key,
                },
            )
        except Exception as e:
            print()
            logging.error(e)
            raise


class BatchEmbeddingUser(HttpUser):
    """
    BatchEmbeddingUser makes calls to the OpenAI Embeddings endpoint to show traffic via APIM and sets the is-batch query string value
    """

    wait_time = constant(1)  # wait 1 second between requests

    @task
    def get_completion(self):
        url = f"openai/deployments/{deployment_name}/embeddings?api-version=2023-05-15&is-batch=true"
        payload = {
            "input": input_text,
            "model": "embedding",
        }
        try:
            self.client.post(
                url,
                json=payload,
                headers={
                    "ocp-apim-subscription-key": apim_subscription_one_key,
                },
            )
        except Exception as e:
            print()
            logging.error(e)
            raise


@events.init.add_listener
def on_locust_init(environment, **kwargs):
    """
    Configure logging/metric collection
    """
    if app_insights_connection_string:
        logging.info("App Insights connection string found - enabling request metrics")
        environment.events.request.add_listener(report_request_metric)
    else:
        logging.warning(
            "App Insights connection string not found - request metrics disabled"
        )

    # Tweak the logging output :-)
    # logging.getLogger("locust").setLevel(logging.WARNING)


@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    """
    Initialize simulator/APIM
    """
    global test_start_time
    test_start_time = datetime.now(UTC)
    logging.info("👟 Setting up test...")

    logging.info("⚙️ Resetting simulator latencies")
    set_simulator_chat_completions_latency(simulator_endpoint_payg1, 1)

    logging.info("👟 Test setup done")
    logging.info("🚀 Running test...")


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    """
    Collect metrics and show results
    """
    test_stop_time = datetime.now(UTC)
    logging.info("✔️ Test finished")

    query_processor = QueryProcessor(
        workspace_id=log_analytics_workspace_id,
        token_credential=DefaultAzureCredential(),
        tenant_id=tenant_id,
        subscription_id=subscription_id,
        resource_group_name=resource_group_name,
        workspace_name=log_analytics_workspace_name,
    )

    time_range = f"TimeGenerated > datetime({test_start_time.strftime('%Y-%m-%dT%H:%M:%SZ')}) and TimeGenerated < datetime({test_stop_time.strftime('%Y-%m-%dT%H:%M:%SZ')})"
    logging.info(f"Query time range: {time_range}")

    metric_check_time = test_stop_time - timedelta(seconds=10)
    check_results_query = f"""
    ApiManagementGatewayLogs
    | where TimeGenerated >= datetime({metric_check_time.strftime('%Y-%m-%dT%H:%M:%SZ')})
    | count
    """
    query_processor.wait_for_non_zero_count(check_results_query)

    query_processor.add_query(
        title="Overall request count",
        query=f"""
ApiManagementGatewayLogs
| where OperationName != "" and  {time_range}
| where BackendId != ""
| summarize request_count = count() by bin(TimeGenerated, 10s)
| order by TimeGenerated asc
| render timechart
        """.strip(),  # When clicking on the link, Log Analytics runs the query automatically if there's no preceding whitespace
        is_chart=True,
        columns=["request_count"],
        chart_config={
            "height": 15,
            "min": 0,
            "colors": [
                asciichart.yellow,
                asciichart.blue,
            ],
        },
        timespan=(test_start_time, test_stop_time),
        show_query=True,
        include_link=True,
    )

    query_processor.add_query(
        title="Request count by backend (PTU1 -> Blue, PAYG1 -> Yellow)",
        query=f"""
ApiManagementGatewayLogs
| where OperationName != "" and  {time_range}
| where BackendId != ""
| extend is_batch = parse_url(Url)["Query Parameters"]["is-batch"] == "true"
| extend label = strcat(iif(is_batch, "batch", "non-batch"), "-", ResponseCode)
| summarize request_count = count() by bin(TimeGenerated, 10s), label
| project TimeGenerated, request_count, label
| order by TimeGenerated asc
| render timechart
""".strip(),  # When clicking on the link, Log Analytics runs the query automatically if there's no preceding whitespace
        is_chart=True,
        chart_config={
            "height": 15,
            "min": 0,
            "colors": [
                asciichart.yellow,
                asciichart.lightyellow,
                asciichart.blue,
                asciichart.lightblue,
            ],
        },
        group_definition=GroupDefinition(
            id_column="TimeGenerated",
            group_column="label",
            value_column="request_count",
            missing_value=float("nan"),
        ),
        timespan=(test_start_time, test_stop_time),
        show_query=True,
        include_link=True,
    )

    query_processor.run_queries()
