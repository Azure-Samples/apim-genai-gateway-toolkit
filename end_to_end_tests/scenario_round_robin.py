from datetime import datetime, timedelta, UTC
import logging
import time

import asciichartpy as asciichart
from azure.identity import DefaultAzureCredential
from locust import HttpUser, task, constant, events

from common.app_insights import (
    GroupDefinition,
    QueryProcessor,
    parse_app_id_from_connection_string,
)
from common.latency import (
    measure_latency_and_update_apim,
    set_simulator_completions_latency,
    report_request_metric,
)
from common.config import (
    apim_key,
    app_insights_connection_string,
    simulator_endpoint_payg1,
    simulator_endpoint_payg2,
    tenant_id,
    subscription_id,
    resource_group_name,
    app_insights_name,
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
            headers={"ocp-apim-subscription-key": apim_key},
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

    app_id = parse_app_id_from_connection_string(app_insights_connection_string)

    query_processor = QueryProcessor(
        app_id=app_id,
        token_credential=DefaultAzureCredential(),
        tenant_id=tenant_id,
        subscription_id=subscription_id,
        resource_group_name=resource_group_name,
        app_insights_name=app_insights_name,
    )

    metric_check_time = test_stop_time - timedelta(seconds=10)
    check_results_query = f"""
    customMetrics
    | where timestamp >= datetime({metric_check_time.strftime('%Y-%m-%dT%H:%M:%SZ')}) and name == "locust.request_latency"
    | count
    """
    query_processor.wait_for_non_zero_count(check_results_query)

    time_range = f"timestamp > datetime({test_start_time.strftime('%Y-%m-%dT%H:%M:%SZ')}) and timestamp < datetime({test_stop_time.strftime('%Y-%m-%dT%H:%M:%SZ')})"

    query_processor.add_query(
        title="Back-end API request count (PAYG1 -> Blue, PAYG2 -> Yellow)",
        query=f"""
        customMetrics
        | where name == "aoai-simulator.latency.full" and {time_range}
        | project timestamp, cloud_RoleName, valueCount
        | summarize request_count = sum(valueCount) by cloud_RoleName, bin(timestamp, 10s)
        | order by timestamp asc
        | render timechart 
        """,
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
            id_column="timestamp",
            group_column="cloud_RoleName",
            value_column="request_count",
            missing_value=float("nan"),
        ),
        timespan="P1D",
        show_query=True,
        include_link=True,
    )

    query_processor.run_queries()
