import logging
import os
import time
import requests

from opentelemetry import metrics
from azure.monitor.opentelemetry import configure_azure_monitor


apim_key = os.getenv("APIM_KEY")
apim_endpoint = os.getenv("APIM_ENDPOINT")
app_insights_connection_string = os.getenv("APP_INSIGHTS_CONNECTION_STRING")
simulator_endpoint_payg1 = os.getenv("SIMULATOR_ENDPOINT_PAYG1")
simulator_endpoint_payg2 = os.getenv("SIMULATOR_ENDPOINT_PAYG2")
simulator_api_key = os.getenv("SIMULATOR_API_KEY")

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


def measure_latency_and_update_apim():
    """
    Make calls to the simulator endpoints to measure the latency.
    Then call the helper API published in APIM to pass this information
    so that it can be used in the latency-routing policy
    In a real scenario, this would be scheduled to run periodically
    """

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

    endpoints = [
        f"{simulator_endpoint_payg1}/openai",
        f"{simulator_endpoint_payg2}/openai",
    ]
    endpoints_with_latency = [
        {
            "endpoint": endpoint,
            "latency": measure_latency(endpoint),
        }
        for endpoint in endpoints
    ]

    # sort with lowest latency first
    endpoints_with_latency = sorted(endpoints_with_latency, key=lambda x: x["latency"])
    logging.info(">>> Endpoints with latency: %s", str(endpoints_with_latency))
    sorted_endpoints = [endpoint["endpoint"] for endpoint in endpoints_with_latency]

    payload = {"preferredBackends": sorted_endpoints}
    response = requests.post(
        url=f"{apim_endpoint}/helpers/set-preferred-backends",
        json=payload,
        headers={"ocp-apim-subscription-key": apim_key},
    )
    response.raise_for_status()
    logging.info("Updated APIM with preferred backends: %s", response.text)
