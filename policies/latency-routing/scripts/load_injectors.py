import logging
import time
from locust import HttpUser, task, constant, events

from common.helpers import (
    measure_latency_and_update_apim,
    set_simulator_completions_latency,
    report_request_metric,
    apim_key,
    app_insights_connection_string,
    simulator_endpoint_payg1,
    simulator_endpoint_payg2,
)

deployment_name = "gpt-35-turbo-100k-token"


@events.init.add_listener
def on_locust_init(environment, **kwargs):
    if app_insights_connection_string:
        logging.info("App Insights connection string found - enabling request metrics")
        environment.events.request.add_listener(report_request_metric)
    else:
        logging.warning(
            "App Insights connection string not found - request metrics disabled"
        )


@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    logging.info("⚙️ Setting initial simulator latencies (PAYG1 fast, PAYG2 slow)")
    set_simulator_completions_latency(simulator_endpoint_payg1, 10)
    set_simulator_completions_latency(simulator_endpoint_payg2, 1000)

    time.sleep(1)
    logging.info("⌚ Measuring API latencies and updating APIM")
    measure_latency_and_update_apim()

    logging.info("🚀 test_start done")


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


class TestCoordinationUser(HttpUser):
    """
    TestCoordinationUser controls the request latencies etc to automate the demo
    """

    fixed_count = 1  # ensure we only have a single instance of this user

    @task
    def orchestrate_test(self):
        time.sleep(120)  # sleep for 2 minutes

        # Reverse the latencies
        logging.info("⚙️ Updating simulator latencies (PAYG1 slow, PAYG2 fast)")
        set_simulator_completions_latency(simulator_endpoint_payg1, 1000)
        set_simulator_completions_latency(simulator_endpoint_payg2, 10)

        # wait so that there's time to see the effect in the telemetry
        time.sleep(30)

        # Measure the latencies and update APIM
        logging.info("⌚ Measuring latencies and updating APIM")
        measure_latency_and_update_apim()

        time.sleep(120)  # sleep for 2 minutes
