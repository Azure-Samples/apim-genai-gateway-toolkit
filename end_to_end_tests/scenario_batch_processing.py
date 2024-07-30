from datetime import datetime, timedelta, UTC
import logging

import asciichartpy as asciichart
from azure.identity import DefaultAzureCredential
from locust import HttpUser, LoadTestShape, task, constant, events
from locust.clients import HttpSession

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
    app_insights_name,
    app_insights_connection_string,
    log_analytics_workspace_id,
    log_analytics_workspace_name,
)

test_start_time = None
deployment_name = "embedding100k"

# use short input text to validate request-based limiting, longer text to validate token-based limiting
# input_text = "This is some text to generate embeddings for
input_text = "Lorem ipsum dolor sit amet."

def make_completion_request(client: HttpSession, max_tokens: int, batch: bool):
    extra_query_string = "&is-batch=true" if batch else ""
    url = f"openai/deployments/{deployment_name}/embeddings?api-version=2023-05-15{extra_query_string}"
    payload = {
        "input": input_text,
        "model": "embedding",
        "max_tokens": max_tokens,
    }
    try:
        client.post(
            url,
            json=payload,
            headers={
                "ocp-apim-subscription-key": apim_subscription_one_key,
            },
        )
    except Exception as e:
        logging.error(e)
        raise

class NonBatchEmbeddingUser(HttpUser):
    """
    """

    wait_time = constant(1)  # wait 1 second between requests

    @task
    def get_completion_non_batch(self):
        make_completion_request(self.client, 200, False)

class NonBatchHighTokenEmbeddingUser(HttpUser):
    """
    """

    wait_time = constant(1)  # wait 1 second between requests

    @task
    def get_completion_non_batch(self):
        make_completion_request(self.client, 1000, False)

class BatchEmbeddingUser(HttpUser):
    """
    """

    wait_time = constant(1)  # wait 1 second between requests

    @task
    def get_completion_batch(self):
        make_completion_request(self.client, 200, True)

class MixedEmbeddingUser(HttpUser):
    """
    """

    wait_time = constant(1)  # wait 1 second between requests

    @task
    def get_completion_non_batch(self):
        make_completion_request(self.client, 200, False)

    @task
    def get_completion(self):
        make_completion_request(self.client, 200, True)

class StagesShape(LoadTestShape):
    """
    Custom LoadTestShape to simulate a spike in traffic part way through the test
    """

    # See https://docs.locust.io/en/stable/custom-load-shape.html
    stages = [
        # Total Limits: 100000 TPM and 100 RP10S
        # Batch Threshold: 30000 TPM and 30 RP10S
        # 20 RP10S, 24000 TPM (show 200s for interactive requests)
        {"duration": 60, "users": 2, "spawn_rate": 1, "user_classes": [NonBatchEmbeddingUser]},
        # 120 RP10S, 144000 TPM (show 429s for interactive requests due to rp10s limit)
        {"duration": 120, "users": 12, "spawn_rate": 1, "user_classes": [NonBatchEmbeddingUser]},
        # 20 RP10S, 24000 TPM (show 200s for interactive requests)
        {"duration": 180, "users": 2, "spawn_rate": 1, "user_classes": [NonBatchEmbeddingUser]},
        # scale back down to 0 users
        {"duration": 190, "users": 0, "spawn_rate": 1, "user_classes": [NonBatchEmbeddingUser]},
        # 30 RP10S, 180000 TPM (show 429s for interactive requests due to tpm limit)
        {"duration": 250, "users": 3, "spawn_rate": 1, "user_classes": [NonBatchHighTokenEmbeddingUser]},
        # scale back down to 0 users
        {"duration": 260, "users": 0, "spawn_rate": 1, "user_classes": [NonBatchHighTokenEmbeddingUser]},
        # 50 RP10S, 60000 TPM (show 200s for both interactive and batch requests)
        {"duration": 320, "users": 5, "spawn_rate": 1, "user_classes": [MixedEmbeddingUser]},
        # 120 RP10S, 144000 TPM (show 200s for interactive requests and 429s for batch requests)
        {"duration": 370, "users": 12, "spawn_rate": 1, "user_classes": [MixedEmbeddingUser]},
        # scale back down to 0 users
        {"duration": 380, "users": 0, "spawn_rate": 1, "user_classes": [MixedEmbeddingUser]},
        # 20 RP10S, 24000 TPM (show 200s for batch requests)
        {"duration": 440, "users": 2, "spawn_rate": 1, "user_classes": [BatchEmbeddingUser]},
    ]

    def tick(self):
        run_time = self.get_run_time()

        for stage in self.stages:
            if run_time < stage["duration"]:
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
        app_insights_name=app_insights_name,
    )

    metric_check_time = test_stop_time - timedelta(seconds=10)
    check_results_query = f"""
    ApiManagementGatewayLogs
    | where TimeGenerated >= datetime({metric_check_time.strftime('%Y-%m-%dT%H:%M:%SZ')})
    | count
    """
    query_processor.wait_for_non_zero_count(check_results_query)

    time_range = f"TimeGenerated > datetime({test_start_time.strftime('%Y-%m-%dT%H:%M:%SZ')}) and TimeGenerated < datetime({test_stop_time.strftime('%Y-%m-%dT%H:%M:%SZ')})"

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
        title="Request count by batch status",
        query=f"""
ApiManagementGatewayLogs
| where OperationName != "" and  {time_range}
| where BackendId != ""
| extend is_batch = parse_url(Url)["Query Parameters"]["is-batch"] == "true"
| extend label = strcat(iif(is_batch, "batch", "non-batch"))
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

    query_processor.add_query(
        title="Request count by batch status and response code",
        query=f"""
ApiManagementGatewayLogs
| where OperationName != "" and  {time_range}
| where BackendId != ""
| extend is_batch = parse_url(Url)["Query Parameters"]["is-batch"] == "true"
| extend label = strcat(iif(is_batch, "batch", "non-batch"), "-", ResponseCode)
| summarize request_count = count() by bin(TimeGenerated, 10s), label
| project TimeGenerated, request_count, label
| order by TimeGenerated asc
| render areachart
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

    query_processor.add_query(
        title="Consumed tokens",
        query=f"""
AppMetrics
| where Name== "ConsumedTokens" and {time_range}
| extend IsBatch = tobool(Properties["IsBatch"])
| extend label = iif(IsBatch, "Batch", "Non-Batch")
| summarize tokens=sum(Sum) by bin(TimeGenerated, 10s), label
| render timechart         
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
            value_column="tokens",
            missing_value=float("nan"),
        ),
        timespan=(test_start_time, test_stop_time),
        show_query=True,
        include_link=True,
    )

    query_processor.run_queries()
