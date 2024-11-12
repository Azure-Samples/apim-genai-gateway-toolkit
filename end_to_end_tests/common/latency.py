import logging
import os
import time
import requests

from opentelemetry import metrics
from azure.monitor.opentelemetry import configure_azure_monitor

from .config import (
    apim_endpoint,
    apim_subscription_one_key,
    app_insights_connection_string,
    simulator_api_key,
    simulator_endpoint_payg1,
    simulator_endpoint_payg2,
)

deployment_name = "gpt-35-turbo-100k-token"

histogram_request_latency: metrics.Histogram

if app_insights_connection_string:
    # Options: https://github.com/Azure/azure-sdk-for-python/tree/main/sdk/monitor/azure-monitor-opentelemetry#usage
    logging.getLogger("azure").setLevel(logging.WARNING)
    configure_azure_monitor(connection_string=app_insights_connection_string)
    histogram_request_latency = metrics.get_meter(__name__).create_histogram(
        "locust.request_latency", "Request latency", "s"
    )


def report_request_metric(
    request_type, name, response_time, response_length, exception, **kwargs
):
    if not exception:
        # response_time is in milliseconds
        response_time_s = response_time / 1000
        histogram_request_latency.record(response_time_s)


def set_simulator_completions_latency(endpoint: str, latency: float):
    """
    Set the latency for the simulator completions endpoint

    :param endpoint: The simulator endpoint to set the latency for
    :param latency: The latency to set - specified in milliseconds per completion token
    """

    url = f"{endpoint}/++/config"
    response = requests.patch(
        url=url,
        headers={"api-key": simulator_api_key, "Content-Type": "application/json"},
        json={"latency": {"open_ai_completions": {"mean": latency}}},
        timeout=10,
    )
    response.raise_for_status()


def set_simulator_chat_completions_latency(endpoint: str, latency: float):
    """
    Set the latency for the simulator completions endpoint

    :param endpoint: The simulator endpoint to set the latency for
    :param latency: The latency to set - specified in milliseconds per chat completion token
    """

    url = f"{endpoint}/++/config"
    response = requests.patch(
        url=url,
        headers={"api-key": simulator_api_key, "Content-Type": "application/json"},
        json={"latency": {"open_ai_chat_completions": {"mean": latency}}},
        timeout=10,
    )
    response.raise_for_status()


def measure_latency_and_update_apim():
    """
    Make calls to the simulator endpoints to measure the latency.
    Then call the helper API published in APIM to pass this information
    so that it can be used in the latency-routing policy
    In a real scenario, this would be scheduled to run periodically
    """

    # There are various considerations to take into account when measuring the latency
    # to compare across endpoints.
    # For example, do you want to measure the time for a complete response or the
    # time to receive the first token (via streaming)?
    # Also, the response time for a full response will be heavily affected by the number
    # of generated tokens in the response
    # The measurement used here takes a balanced view by measuring the time to receive the full
    # response but setting max_tokens to 10 to limit the degree of variation in the
    # number of tokens in the response (and hence the response time)

    def measure_latency(endpoint: str):
        """Helper to measure the latency of an endpoint"""
        time_start = time.perf_counter()
        try:
            response = requests.post(
                url=f"{endpoint}/deployments/{deployment_name}/completions?api-version=2023-05-15",
                headers={
                    "api-key": simulator_api_key,
                    "Content-Type": "application/json",
                },
                json={
                    "model": "gpt-5-turbo-1",
                    "prompt": "Once upon a time",
                    "max_tokens": 10,
                },
                timeout=30,
            )
            response.raise_for_status()
            time_end = time.perf_counter()
            return time_end - time_start
        except requests.ReadTimeout:
            logging.warning("Request to %s timed out", endpoint)
            return float("inf")

    backends = [
        {
            "endpoint": f"{simulator_endpoint_payg1}/openai",
            "backend-id": "payg-backend-1",
        },
        {
            "endpoint": f"{simulator_endpoint_payg2}/openai",
            "backend-id": "payg-backend-2",
        },
    ]
    backends_with_latency = [
        {
            "endpoint": backend["endpoint"],
            "backend-id": backend["backend-id"],
            "latency": measure_latency(backend["endpoint"]),
        }
        for backend in backends
    ]

    # sort with lowest latency first
    backends_with_latency = sorted(backends_with_latency, key=lambda x: x["latency"])
    for backend in backends_with_latency:
        logging.info(
            "    %s: %s ms",
            backend["endpoint"],
            backend["latency"] * 1000,
        )
    sorted_backends = [backend["backend-id"] for backend in backends_with_latency]

    payload = {"preferredBackends": sorted_backends}
    response = requests.post(
        url=f"{apim_endpoint}/helpers/set-preferred-backends",
        json=payload,
        headers={"api-key": apim_subscription_one_key},
    )
    response.raise_for_status()
    logging.info("    Updated APIM with preferred backends: %s", response.text)
