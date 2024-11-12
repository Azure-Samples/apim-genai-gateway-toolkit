from datetime import datetime, timedelta, UTC
import logging

import asciichartpy as asciichart
from azure.identity import DefaultAzureCredential
from locust import HttpUser, task, constant, events

from common.log_analytics import (
    GroupDefinition,
    QueryProcessor,
)
from common.latency import (
    set_simulator_completions_latency,
    report_request_metric,
)
from common.config import (
    apim_subscription_one_key,
    simulator_endpoint_payg1,
    simulator_endpoint_payg2,
    tenant_id,
    subscription_id,
    resource_group_name,
    app_insights_connection_string,
    log_analytics_workspace_id,
    log_analytics_workspace_name,
)

test_start_time = None
deployment_name = "gpt-35-turbo-100m-token"


class CompletionUser(HttpUser):
    """
    CompletionUser makes calls to the OpenAI Completions endpoint to show traffic via APIM
    """

    wait_time = constant(1)  # wait 1 second between requests

    @task
    def get_completion(self):
        url = f"openai/deployments/{deployment_name}/completions?api-version=2023-05-15"
        payload = {
            "model": "gpt-5-turbo-1",
            "prompt": "Once upon a time",
            "max_tokens": 10,
        }
        self.client.post(
            url,
            json=payload,
            headers={"api-key": apim_subscription_one_key},
        )


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
    logging.getLogger("locust").setLevel(logging.WARNING)


@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    """
    Initialize simulator/APIM
    """
    global test_start_time
    test_start_time = datetime.now(UTC)
    logging.info("👟 Setting up test...")

    logging.info("⚙️ Resetting simulator latencies")
    set_simulator_completions_latency(simulator_endpoint_payg1, 10)
    set_simulator_completions_latency(simulator_endpoint_payg2, 10)

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

    metric_check_time = test_stop_time - timedelta(seconds=10)
    check_results_query = f"""
    AppMetrics
    | where TimeGenerated >= datetime({metric_check_time.strftime('%Y-%m-%dT%H:%M:%SZ')}) and Name == "locust.request_latency"
    | count
    """
    query_processor.wait_for_non_zero_count(check_results_query)

    time_range = f"TimeGenerated > datetime({test_start_time.strftime('%Y-%m-%dT%H:%M:%SZ')}) and TimeGenerated < datetime({test_stop_time.strftime('%Y-%m-%dT%H:%M:%SZ')})"

    query_processor.add_query(
        title="Request count by backend (PAYG1 -> Blue, PAYG2 -> Yellow)",
        query=f"""
ApiManagementGatewayLogs
| where OperationName != "" and  {time_range}
| where BackendId != ""
| summarize request_count = count() by bin(TimeGenerated, 10s), BackendId
| order by TimeGenerated asc
| render timechart
        """.strip(),  # When clicking on the link, Log Analytics runs the query automatically if there's no preceding whitespace,
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
            group_column="BackendId",
            value_column="request_count",
            missing_value=float("nan"),
        ),
        timespan=(test_start_time, test_stop_time),
        show_query=True,
        include_link=True,
    )

    query_processor.add_query(
        title="Total requests (by backend)",
        query=f"""
ApiManagementGatewayLogs
| where OperationName != "" and  {time_range}
| where BackendId != ""
| summarize request_count = count() by BackendId
| evaluate pivot(BackendId, sum(request_count))
        """.strip(),  # When clicking on the link, Log Analytics runs the query automatically if there's no preceding whitespace,
        timespan=(test_start_time, test_stop_time),
        show_query=True,
        include_link=True,
    )
    query_processor.run_queries(
        all_queries_link_text="Show all queries in Log Analytics"
    )
