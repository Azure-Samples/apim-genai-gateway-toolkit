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
    simulator_endpoint_ptu1,
    simulator_endpoint_payg1,
    tenant_id,
    subscription_id,
    resource_group_name,
    app_insights_connection_string,
    log_analytics_workspace_id,
    log_analytics_workspace_name,
)

test_start_time = None
deployment_name = "gpt-35-turbo-100k-token"


class StagesShape(LoadTestShape):
    """
    Custom LoadTestShape to simulate a spike in traffic part way through the test
    """

    # See https://docs.locust.io/en/stable/custom-load-shape.html
    stages = [
        {"duration": 180, "users": 2, "spawn_rate": 0.1},
        {"duration": 360, "users": 6, "spawn_rate": 1},
    ]

    def tick(self):
        run_time = self.get_run_time()

        for stage in self.stages:
            if run_time < stage["duration"]:
                return (stage["users"], stage["spawn_rate"])

        return None


class ChatCompletionUser(HttpUser):
    """
    CompletionUser makes calls to the OpenAI Chat Completions endpoint to show traffic via APIM
    """

    wait_time = constant(1)  # wait 1 second between requests

    @task
    def get_completion(self):
        url = f"openai/deployments/{deployment_name}/chat/completions?api-version=2023-05-15"
        payload = {
            "messages": [
                {"role": "user", "content": "Lorem ipsum dolor sit amet?"},
                {
                    "role": "assistant",
                    "content": "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.",
                },
                {"role": "user", "content": "Ut enim ad minim veniam?"},
                {
                    "role": "assistant",
                    "content": "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.",
                },
                {"role": "user", "content": "Lorem ipsum dolor sit amet?"},
                {
                    "role": "assistant",
                    "content": "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.",
                },
                {"role": "user", "content": "Ut enim ad minim veniam?"},
                {
                    "role": "assistant",
                    "content": "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.",
                },
                {"role": "user", "content": "Lorem ipsum dolor sit amet?"},
                {
                    "role": "assistant",
                    "content": "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.",
                },
                {"role": "user", "content": "Ut enim ad minim veniam?"},
                {
                    "role": "assistant",
                    "content": "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.",
                },
                {"role": "user", "content": "Lorem ipsum dolor sit amet?"},
                {
                    "role": "assistant",
                    "content": "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.",
                },
                {"role": "user", "content": "Ut enim ad minim veniam?"},
                {
                    "role": "assistant",
                    "content": "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.",
                },
                {"role": "user", "content": "Duis aute irure dolor in reprehenderit?"},
            ],
            "model": "gpt-5-turbo-1",
            "max_tokens": 1000,
        }
        try:
            self.client.post(
                url,
                json=payload,
                headers={"api-key": apim_subscription_one_key},
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
    set_simulator_chat_completions_latency(simulator_endpoint_ptu1, 1)
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

    metric_check_time = test_stop_time - timedelta(seconds=10)
    check_results_query = f"""
    AppMetrics
    | where TimeGenerated >= datetime({metric_check_time.strftime('%Y-%m-%dT%H:%M:%SZ')}) and Name == "locust.request_latency"
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
        title="Request count by backend (PTU1 -> Blue, PAYG1 -> Yellow)",
        query=f"""
ApiManagementGatewayLogs
| where OperationName != "" and  {time_range}
| where BackendId != ""
| summarize request_count = count() by bin(TimeGenerated, 10s), BackendId
| order by TimeGenerated asc
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
            group_column="BackendId",
            value_column="request_count",
            missing_value=float("nan"),
        ),
        timespan=(test_start_time, test_stop_time),
        show_query=True,
        include_link=True,
    )

    query_processor.run_queries(
        all_queries_link_text="Show all queries in Log Analytics"
    )
