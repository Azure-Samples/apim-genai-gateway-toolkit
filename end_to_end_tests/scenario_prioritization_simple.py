from datetime import datetime, timedelta, UTC
import logging

import asciichartpy as asciichart
from azure.identity import DefaultAzureCredential
from locust import HttpUser, LoadTestShape, task, constant, events
from locust.clients import HttpSession
from opentelemetry import metrics

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


histogram_request_result = metrics.get_meter(__name__).create_histogram(
    "locust.request_result", "Request Response", "count"
)


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


# use short input text to validate request-based limiting, longer text to validate token-based limiting
# TODO - split tests!
# input_text = "This is some text to generate embeddings for
input_text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Habitant morbi tristique senectus et netus et malesuada. Bibendum neque egestas congue quisque egestas diam. Rutrum quisque non tellus orci ac auctor augue. Diam in arcu cursus euismod quis. Euismod elementum nisi quis eleifend quam adipiscing. Posuere lorem ipsum dolor sit amet consectetur adipiscing elit duis. Pretium vulputate sapien nec sagittis aliquam malesuada bibendum arcu. Adipiscing diam donec adipiscing tristique risus nec. Nec ultrices dui sapien eget mi proin. Odio facilisis mauris sit amet. Eget aliquet nibh praesent tristique magna. Malesuada nunc vel risus commodo viverra maecenas accumsan lacus vel. Maecenas volutpat blandit aliquam etiam erat velit scelerisque in dictum. Venenatis tellus in metus vulputate. Aliquet enim tortor at auctor urna nunc id cursus metus. Sed velit dignissim sodales ut eu sem integer vitae justo."


# TODO - use env var to request type (embeddings vs chat vs streaming chat)
def make_request(client: HttpSession, batch: bool):
    url = f"openai/deployments/{deployment_name}/embeddings?api-version=2023-05-15"
    payload = {
        "input": input_text,
        "model": "embedding",
    }
    try:
        r = client.post(
            url,
            json=payload,
            headers={
                "ocp-apim-subscription-key": apim_subscription_one_key,
                "x-is-batch": "true" if batch else "false",
            },
        )
        histogram_request_result.record(
            1,
            {
                "status_code": str(r.status_code),
                "batch": str(batch),
                "reason": r.reason,
            },
        )

    except Exception as e:

        logging.error(e)
        raise


class NonBatchUser(HttpUser):
    """
    NonBatchUser makes calls to the OpenAI endpoint to show traffic via APIM
    """

    wait_time = constant(1)  # wait 1 second between requests

    @task
    def make_request_non_batch(self):
        make_request(self.client, False)


class BatchUser(HttpUser):
    """
    BatchUser makes calls to the OpenAI endpoint to show traffic via APIM and sets the is-batch query string value
    """

    wait_time = constant(1)  # wait 1 second between requests

    @task
    def make_request_batch(self):
        make_request(self.client, True)


class MixedUser_1_1(HttpUser):
    """
    MixedUser_1_1 makes calls to the OpenAI endpoint to show traffic via APIM.
    It has a 1:1 ratio of batch to non-batch requests.
    """

    wait_time = constant(1)  # wait 1 second between requests

    @task
    def make_request_non_batch(self):
        make_request(self.client, False)

    @task
    def make_request_batch(self):
        make_request(self.client, True)


class StagesShape(LoadTestShape):
    """
    Custom LoadTestShape to simulate variations in non-batch and batch processing
    """

    # See https://docs.locust.io/en/stable/custom-load-shape.html
    stages = [
        # Start with batch processing
        {
            "duration": 120,
            "users": 9,
            "spawn_rate": 1,
            "user_classes": [BatchUser],
        },
        # Add non-batch
        {
            "duration": 240,
            "users": 18,
            "spawn_rate": 1,
            "user_classes": [MixedUser_1_1],
        },
        # Stop batch processing
        {
            "duration": 360,
            "users": 9,
            "spawn_rate": 1,
            "user_classes": [NonBatchUser],
        },
        # Add batch back in
        {
            "duration": 480,
            "users": 18,
            "spawn_rate": 1,
            "user_classes": [MixedUser_1_1],
        },
        # Switch to only batch
        {
            "duration": 600,
            "users": 9,
            "spawn_rate": 1,
            "user_classes": [BatchUser],
        },
        # # {"duration": 60, "users": 4, "spawn_rate": 1},
        # # {"duration": 120, "users": 8, "spawn_rate": 1},
        # # {"duration": 180, "users": 12, "spawn_rate": 1},
        # # {"duration": 240, "users": 16, "spawn_rate": 1},
        # # {"duration": 300, "users": 20, "spawn_rate": 1},
    ]

    _current_stage = stages[0]

    def tick(self):
        run_time = self.get_run_time()

        for stage in self.stages:
            if run_time < stage["duration"]:
                if self._current_stage and self._current_stage != stage:
                    # temp scale down as existing users that don't match the user_classes aren't removed
                    # https://github.com/locustio/locust/issues/2714
                    self._current_stage = stage
                    return (0, 100)

                try:
                    tick_data = (
                        stage["users"],
                        stage["spawn_rate"],
                        stage["user_classes"],
                    )
                except:
                    tick_data = (stage["users"], stage["spawn_rate"])
                return tick_data
        return None


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
    time_vars = f"let startTime = datetime({test_start_time.strftime('%Y-%m-%dT%H:%M:%SZ')});\nlet endTime = datetime({test_stop_time.strftime('%Y-%m-%dT%H:%M:%SZ')});"
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
{time_vars}
ApiManagementGatewayLogs
| where OperationName != "" and  TimeGenerated > startTime and TimeGenerated < endTime
| where BackendId != ""
| summarize request_count = count() by bin(TimeGenerated, 10s)
| order by TimeGenerated asc
| render timechart with (title="Overall request count")
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
        title="Successful request count by request type (Non-batch -> Blue, Batch -> Yellow)",
        query=f"""
{time_vars}
ApiManagementGatewayLogs
| where OperationName != "" and  TimeGenerated > startTime and TimeGenerated < endTime
| where BackendId != ""
| where ResponseCode == 200
| extend is_batch = parse_url(Url)["Query Parameters"]["is-batch"] == "true"
| extend label = iif(is_batch, "batch", "non-batch")
| summarize request_count = count() by bin(TimeGenerated, 10s), label
| order by TimeGenerated asc
| render timechart with (title="Successful request count by request type")
        """.strip(),  # When clicking on the link, Log Analytics runs the query automatically if there's no preceding whitespace
        is_chart=True,
        chart_config={
            "height": 15,
            "min": 0,
            "colors": [
                asciichart.yellow,
                asciichart.blue,
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

    query_processor.add_query(
        title="Remaining tokens (Min -> Blue, Max -> Yellow, Avg -> Green)",
        query=f"""
{time_vars}
ApiManagementGatewayLogs
| where TimeGenerated > startTime and TimeGenerated < endTime
| extend 
    remaining_tokens = toint(ResponseHeaders["x-gw-remaining-tokens"])
| summarize max_remaining_tokens=max(remaining_tokens), min_remaining_tokens=min(remaining_tokens), avg_remaining_tokens=sum(remaining_tokens)/count(remaining_tokens) by bin(TimeGenerated, 10s)
| render timechart with (title="Remaining tokens")
        """.strip(),  # When clicking on the link, Log Analytics runs the query automatically if there's no preceding whitespace
        is_chart=True,
        columns=[
            "max_remaining_tokens",
            "min_remaining_tokens",
            "avg_remaining_tokens",
        ],
        chart_config={
            "height": 15,
            "min": 0,
            "colors": [
                asciichart.yellow,
                asciichart.blue,
                asciichart.green,
            ],
        },
        timespan=(test_start_time, test_stop_time),
        show_query=True,
        include_link=True,
    )

    query_processor.add_query(
        title="Rate-limit tokens consumed (Simulator metric)",
        query=f"""
{time_vars}
AppMetrics 
| where TimeGenerated > startTime and TimeGenerated < endTime
| where Name == "aoai-simulator.tokens.rate-limit" 
| extend deployment = tostring(Properties["deployment"])
| summarize number=sum(Sum) by bin(TimeGenerated, 10s), deployment
| render timechart with (title="Rate-limit tokens")
        """.strip(),  # When clicking on the link, Log Analytics runs the query automatically if there's no preceding whitespace
        is_chart=True,
        chart_config={
            "height": 15,
            "min": 0,
            "colors": [
                asciichart.yellow,
                asciichart.blue,
                asciichart.green,
            ],
        },
        group_definition=GroupDefinition(
            id_column="TimeGenerated",
            group_column="deployment",
            value_column="number",
            missing_value=float("nan"),
        ),
        timespan=(test_start_time, test_stop_time),
        show_query=True,
        include_link=True,
    )

    query_processor.run_queries()
