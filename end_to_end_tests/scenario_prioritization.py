from datetime import datetime, timedelta, UTC
import logging
import os

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

load_pattern = os.getenv("LOAD_PATTERN", "cycle")
ramp_rate = int(os.getenv("RAMP_RATE", 1))
request_type = os.getenv("REQUEST_TYPE", "embeddings")
max_tokens = int(os.getenv("MAX_TOKENS", "-1"))
endpoint_path = os.getenv("ENDPOINT_PATH")

test_start_time = None

embedding_deployment_name = "embedding100k"
chat_deployment_name = "gpt-35-turbo-100k-token"


print(f"Load pattern: {load_pattern}")
print(f"Ramp rate: {ramp_rate}")
print(f"Embedding deployment name: {embedding_deployment_name}")
print(f"Chat deployment name: {chat_deployment_name}")
print(f"Request type: {request_type}")
print(f"Endpoint path: {endpoint_path}")
if request_type == "chat":
    print(f"Max tokens: {max_tokens}")
elif max_tokens > 0:
    raise ValueError("Max tokens should not be set for non-chat requests")

histogram_request_result = metrics.get_meter(__name__).create_histogram(
    "locust.request_result", "Request Response", "count"
)

# TODO - this file is getting large - consider splitting

# model deployments:
#
# embedding100k
#  - 100k TPM
#  - 600 RPM (10 RPS)


def make_request(client: HttpSession, low_priority: bool):
    if request_type == "embeddings":
        make_embedding_request(client, low_priority)
    elif request_type == "chat":
        make_chat_request(client, low_priority, max_tokens)
    else:
        raise ValueError(f"Unhandled request type: {request_type}")


def make_embedding_request(client: HttpSession, low_priority: bool):
    url = f"openai/deployments/{embedding_deployment_name}/embeddings?api-version=2023-05-15"
    input_text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Habitant morbi tristique senectus et netus et malesuada. Bibendum neque egestas congue quisque egestas diam. Rutrum quisque non tellus orci ac auctor augue. Diam in arcu cursus euismod quis. Euismod elementum nisi quis eleifend quam adipiscing. Posuere lorem ipsum dolor sit amet consectetur adipiscing elit duis. Pretium vulputate sapien nec sagittis aliquam malesuada bibendum arcu. Adipiscing diam donec adipiscing tristique risus nec. Nec ultrices dui sapien eget mi proin. Odio facilisis mauris sit amet. Eget aliquet nibh praesent tristique magna. Malesuada nunc vel risus commodo viverra maecenas accumsan lacus vel. Maecenas volutpat blandit aliquam etiam erat velit scelerisque in dictum. Venenatis tellus in metus vulputate. Aliquet enim tortor at auctor urna nunc id cursus metus. Sed velit dignissim sodales ut eu sem integer vitae justo."
    payload = {
        "input": input_text,
        "model": "embedding",
    }
    try:
        headers = {
            "api-key": apim_subscription_one_key,
        }
        if low_priority:
            headers["x-priority"] = "low"

        r = client.post(url, json=payload, headers=headers)
        histogram_request_result.record(
            1,
            {
                "status_code": str(r.status_code),
                "priority": "low" if low_priority else "high",
                "request_type": "embeddings",
                "reason": r.reason,
            },
        )
    except Exception as e:
        logging.error(e)
        raise


def make_chat_request(client: HttpSession, low_priority: bool, max_tokens: int = 0):
    url = f"openai/deployments/{chat_deployment_name}/chat/completions?api-version=2023-05-15"
    payload = {
        "messages": [
            {"role": "user", "content": "Lorem ipsum dolor sit amet?"},
        ],
        "model": "gpt-35-turbo",
    }
    if max_tokens > 0:
        payload["max_tokens"] = max_tokens
    try:
        headers = {
            "api-key": apim_subscription_one_key,
        }

        if low_priority:
            headers["x-priority"] = "low"

        r = client.post(url, json=payload, headers=headers)
        histogram_request_result.record(
            1,
            {
                "status_code": str(r.status_code),
                "priority": "low" if low_priority else "high",
                "request_type": "chat",
                "reason": r.reason,
            },
        )
    except Exception as e:
        logging.error(e)
        raise


class HighPriorityUser(HttpUser):
    """
    HighPriorityUser makes calls to the OpenAI endpoint to show traffic via APIM
    """

    wait_time = constant(1)  # wait 1 second between requests

    @task
    def make_request_high_priority(self):
        make_request(self.client, False)


class LowPriorityUser(HttpUser):
    """
    LowPriorityUser makes calls to the OpenAI endpoint to show traffic via APIM and sets the x-priority header to "low"
    """

    wait_time = constant(1)  # wait 1 second between requests

    @task
    def make_request_low_priority(self):
        make_request(self.client, True)


class MixedUser_1_1(HttpUser):
    """
    MixedUser_1_1 makes calls to the OpenAI endpoint to show traffic via APIM.
    It has a 1:1 ratio of high to low priority requests.
    """

    wait_time = constant(1)  # wait 1 second between requests

    @task
    def make_request_high_priority(self):
        make_request(self.client, False)

    @task
    def make_request_low_priority(self):
        make_request(self.client, True)


class HighPriorityLowTokenChatUser(HttpUser):
    wait_time = constant(1)  # wait 1 second between requests

    @task
    def get_completion_high_priority(self):
        make_chat_request(self.client, False, 200)


class HighPriorityHighTokenChatUser(HttpUser):
    wait_time = constant(1)  # wait 1 second between requests

    @task
    def get_completion_high_priority(self):
        make_chat_request(self.client, False, 1000)


class LowPriorityLowTokenChatUser(HttpUser):
    wait_time = constant(1)  # wait 1 second between requests

    @task
    def get_completion_low_priority(self):
        make_chat_request(self.client, True, 200)


class MixedPriorityLowTokenChatUser(HttpUser):
    wait_time = constant(1)  # wait 1 second between requests

    @task
    def get_completion_high_priority(self):
        make_chat_request(self.client, False, 200)

    @task
    def get_completion_low_priority(self):
        make_chat_request(self.client, True, 200)


class MixedPriorityHighTokenChatUser(HttpUser):
    wait_time = constant(1)  # wait 1 second between requests

    @task
    def get_completion_high_priority(self):
        make_chat_request(self.client, False, 1000)

    @task
    def get_completion_low_priority(self):
        make_chat_request(self.client, True, 1000)


cycle_stages = [
    # Start with low priority
    {
        "duration": 120,
        "users": 9,
        "spawn_rate": ramp_rate,
        "user_classes": [LowPriorityUser],
    },
    # Add high priority
    {
        "duration": 240,
        "users": 18,
        "spawn_rate": ramp_rate,
        "user_classes": [MixedUser_1_1],
    },
    # Stop low priority
    {
        "duration": 360,
        "users": 9,
        "spawn_rate": ramp_rate,
        "user_classes": [HighPriorityUser],
    },
    # Add low priority back in
    {
        "duration": 480,
        "users": 18,
        "spawn_rate": ramp_rate,
        "user_classes": [MixedUser_1_1],
    },
    # Switch to only low priority
    {
        "duration": 600,
        "users": 9,
        "spawn_rate": ramp_rate,
        "user_classes": [LowPriorityUser],
    },
]
low_priority_stages = [
    # low priority only
    {
        "duration": 300,
        "users": 9,
        "spawn_rate": ramp_rate,
        "user_classes": [LowPriorityUser],
    }
]
high_priority_stages = [
    # high priority only
    {
        "duration": 300,
        "users": 9,
        "spawn_rate": ramp_rate,
        "user_classes": [HighPriorityUser],
    }
]


class StagesShape(LoadTestShape):
    """
    Custom LoadTestShape to simulate variations in high and low priority processing
    """

    def __init__(self):
        super().__init__()

        # See https://docs.locust.io/en/stable/custom-load-shape.html
        if load_pattern == "cycle":
            self.stages = cycle_stages
        elif load_pattern == "low-priority":
            self.stages = low_priority_stages
        elif load_pattern == "high-priority":
            self.stages = high_priority_stages
        else:
            raise ValueError(f"Unhandled load pattern: {load_pattern}")

        self._current_stage = self.stages[0]

    def user_classes_match(stage1, stage2):
        users1 = stage1.get("user_classes", [])
        users2 = stage2.get("user_classes", [])
        if len(users1) != len(users2):
            return False
        for i in range(len(users1)):
            if users1[i] != users2[i]:
                return False
        return True

    def tick(self):
        run_time = self.get_run_time()

        for stage in self.stages:
            if run_time < stage["duration"]:
                if self._current_stage and self._current_stage != stage:
                    if not StagesShape.user_classes_match(self._current_stage, stage):
                        logging.info(
                            f"User classes changed from {self._current_stage.get('user_classes', [])} to {stage.get('user_classes', [])} - scaling down to reset"
                        )
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
        """,
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
        title="Successful request count by request type (High Priority -> Blue, Low Priority -> Yellow)",
        query=f"""
{time_vars}
ApiManagementGatewayLogs
| where OperationName != "" and  TimeGenerated > startTime and TimeGenerated < endTime
| where BackendId != ""
| where ResponseCode == 200
| extend label = strcat(ResponseHeaders["x-gw-priority"], "-priority")
| summarize request_count = count() by bin(TimeGenerated, 10s), label
| order by TimeGenerated asc
| render timechart with (title="Successful request count by request type")
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
        title="Request count by priority and response code",
        query=f"""
{time_vars}
ApiManagementGatewayLogs
| where OperationName != "" and  TimeGenerated > startTime and TimeGenerated < endTime
| where BackendId != ""
| extend label = strcat(ResponseHeaders["x-gw-priority"], "-priority-", ResponseCode)
| summarize request_count = count() by bin(TimeGenerated, 10s), tostring(label)
| project TimeGenerated, request_count, label
| order by TimeGenerated asc
| render areachart with (title="Request count by priority and response code")
""",
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
        title="Remaining tokens (Min -> Blue, Max -> Yellow, Avg -> Green)",
        query=f"""
{time_vars}
ApiManagementGatewayLogs
| where TimeGenerated > startTime and TimeGenerated < endTime
| extend 
    remaining_tokens = toint(ResponseHeaders["x-gw-remaining-tokens"])
| summarize max_remaining_tokens=max(remaining_tokens), min_remaining_tokens=min(remaining_tokens), avg_remaining_tokens=sum(remaining_tokens)/count(remaining_tokens) by bin(TimeGenerated, 10s)
| order by TimeGenerated asc
| render timechart with (title="Remaining tokens")
        """,
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
let interval = 10s;
let timeRange = range TimeStamp from startTime to endTime step interval
| summarize count() by bin(TimeStamp, interval) | project TimeStamp; // align values to interval boundaries
let query = AppMetrics 
| where TimeGenerated > startTime and TimeGenerated < endTime
| where Name == "aoai-api-simulator.tokens.rate-limit" 
| extend deployment = tostring(Properties["deployment"])
| summarize number=sum(Sum) by bin(TimeGenerated, interval), deployment
| order by TimeGenerated asc;
timeRange
| join kind=leftouter query on $left.TimeStamp == $right.TimeGenerated
| project TimeGenerated=TimeStamp, number= coalesce(number, 0.0), deployment=coalesce(deployment, "")
| order by TimeGenerated asc
| serialize 
| extend sliding_average = number 
                + coalesce(prev(number, 1),0.0) 
                + coalesce(prev(number, 2),0.0) 
                + coalesce(prev(number, 3),0.0) 
                + coalesce(prev(number, 5),0.0) 
                + coalesce(prev(number, 6),0.0)
| project TimeGenerated, sliding_average, number
| render timechart with (title="rate-limit tokens (with sliding 60s average)")
""",
        is_chart=True,
        columns=[
            "number",
            "sliding_average",
        ],
        chart_config={
            "height": 15,
            "min": 0,
            "colors": [
                asciichart.yellow,
                asciichart.blue,
            ],
            "format": "{:9.1f}",  # adjust formatting to avoid graph skew for large y-axis values
        },
        timespan=(test_start_time, test_stop_time),
        show_query=True,
        include_link=True,
    )

    if endpoint_path == "prioritization-token-calculating":
        # the ConsumedTokens metrics is only available in the prioritization-token-calculating endpoint
        query_processor.add_query(
            title="Consumed tokens (Gateway)",
            query=f"""
{time_vars}
AppMetrics
| where Name== "ConsumedTokens" and TimeGenerated > startTime and TimeGenerated < endTime
| summarize tokens=sum(Sum) by bin(TimeGenerated, 10s)
| order by TimeGenerated asc
| render timechart with (title="Consumed tokens (Gateway)")
    """,
            is_chart=True,
            columns=["tokens"],
            chart_config={
                "height": 15,
                "min": 0,
                "colors": [
                    asciichart.yellow,
                    asciichart.blue,
                ],
                "format": "{:9.1f}",  # adjust formatting to avoid graph skew for large y-axis values
            },
            timespan=(test_start_time, test_stop_time),
            show_query=True,
            include_link=True,
        )

    query_processor.run_queries(
        all_queries_link_text="Show all queries in Log Analytics"
    )
