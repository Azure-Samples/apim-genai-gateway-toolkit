import base64
from datetime import UTC, datetime, timedelta
import io
import logging
import time
import requests
import urllib.parse
import json
import asciichartpy as asciichart

from azure.core.credentials import TokenCredential
from azure.core.exceptions import HttpResponseError
from azure.monitor.query import LogsQueryClient, MetricsQueryClient, MetricsClient
from dataclasses import dataclass
from gzip import GzipFile
from tabulate import tabulate
from typing import Any

from .terminal import get_link


APPINSIGHTS_ENDPOINT = "https://api.applicationinsights.io/v1/apps"

# https://learn.microsoft.com/en-us/python/api/overview/azure/monitor-query-readme?view=azure-python


## TODO extract this to separate file and share with AppInsights code
@dataclass
class GroupDefinition:
    id_column: str
    group_column: str
    value_column: str
    missing_value: Any = None


@dataclass
class Table:
    columns: list[str]
    rows: list[list[Any]]

    def group_by(
        self,
        id_column: str,
        group_column: str,
        value_column: str,
        missing_value: Any = None,
    ) -> "Table":

        # assume rows are sorted on id_column

        group_column_index = self.columns.index(group_column)
        distinct_group_column_values = sorted(
            list(set(row[group_column_index] for row in self.rows))
        )

        new_columns = [id_column] + [
            f"{value_column}_{name}" for name in distinct_group_column_values
        ]

        id_column_index = self.columns.index(id_column)
        value_column_index = self.columns.index(value_column)

        # Produce a new table where each row has the id_column and a column for each distinct value in group_column with the value of value_column
        rows = []
        current_row = None
        for row in self.rows:
            if current_row is None or current_row[0] != row[id_column_index]:
                if current_row is not None:
                    rows.append(current_row)
                # start new row
                current_row = [row[id_column_index]] + (
                    [missing_value] * len(distinct_group_column_values)
                )
            group = row[group_column_index]
            value = row[value_column_index]
            current_row[distinct_group_column_values.index(group) + 1] = value

        return Table(rows=rows, columns=new_columns)
        
def get_log_analytics_token_metric_url(
    tenant_id: str,
    subscription_id: str,
    resource_group_name: str,
    app_insights_name: str,
    start_time: datetime,
    end_time: datetime
):
    """
    Build a URL to deep link into the Azure Portal to view APIM token metrics in Log Analytics.
    """
    # ensure start and end time are at the top of the minute so that the Azure Metrics blade can properly render the chart
    start = start_time.isoformat()[:-12] + "000Z"
    end = end_time.isoformat()[:-12] + "000Z"
    time_context = {
        "absolute": {
            "startTime": start,
            "endTime": end
        },
        "showUTCTime": False,
        "grain": 1
    }
    time_context_string = json.dumps(time_context, separators=(',', ':'))
    encoded_time_context = urllib.parse.quote(time_context_string)
    # building and encoding the chart_definition JSON object like time_context does not work properly as nested slashes and other special characters are not encoded correctly
    encoded_chart_definition = f"%7B%22v2charts%22%3A%5B%7B%22metrics%22%3A%5B%7B%22resourceMetadata%22%3A%7B%22id%22%3A%22%2Fsubscriptions%2F{subscription_id}%2FresourceGroups%2F{resource_group_name}%2Fproviders%2FMicrosoft.Insights%2Fcomponents%2F{app_insights_name}%22%7D%2C%22name%22%3A%22customMetrics%2FTotal%20Tokens%22%2C%22aggregationType%22%3A1%2C%22namespace%22%3A%22microsoft.insights%2Fcomponents%2Fkusto%22%2C%22metricVisualization%22%3A%7B%22displayName%22%3A%22Total%20Tokens%22%7D%7D%5D%2C%22title%22%3A%22Sum%20Total%20Tokens%20for%20{app_insights_name}%20by%20Subscription%20ID%22%2C%22titleKind%22%3A1%2C%22visualization%22%3A%7B%22chartType%22%3A2%2C%22legendVisualization%22%3A%7B%22isVisible%22%3Atrue%2C%22position%22%3A2%2C%22hideHoverCard%22%3Afalse%2C%22hideLabelNames%22%3Atrue%7D%2C%22axisVisualization%22%3A%7B%22x%22%3A%7B%22isVisible%22%3Atrue%2C%22axisType%22%3A2%7D%2C%22y%22%3A%7B%22isVisible%22%3Atrue%2C%22axisType%22%3A1%7D%7D%7D%2C%22grouping%22%3A%7B%22dimension%22%3A%22customDimensions%2FSubscription%20ID%22%2C%22sort%22%3A2%2C%22top%22%3A10%7D%7D%5D%7D"
    url = f"https://portal.azure.com/#@{tenant_id}/blade/Microsoft_Azure_MonitoringMetrics/Metrics.ReactView/Referer/MetricsExplorer/ResourceId/%2Fsubscriptions%2F{subscription_id}%2FresourceGroups%2F{resource_group_name}%2Fproviders%2FMicrosoft.Insights%2Fcomponents%2F{app_insights_name}/TimeContext/{encoded_time_context}/ChartDefinition/{encoded_chart_definition}"
    link = get_link("View Token Metrics in Log Analytics", url)
    return link

def get_log_analytics_portal_url(
    tenant_id: str,
    subscription_id: str,
    resource_group_name: str,
    workspace_name: str,
    query: str,
):
    """
    Build a URL to deep link into the Azure Portal to run a query in Log Analytics.
    """
    # Get the UTF8 bytes for the query
    query_bytes = query.encode("utf-8")

    # GZip the query bytes
    bio_out = io.BytesIO()
    with GzipFile(mode="wb", fileobj=bio_out) as gzip:
        gzip.write(query_bytes)

    # Base64 encode the result
    zipped_bytes = bio_out.getvalue()
    base64_query = base64.b64encode(zipped_bytes)

    # URL encode the base64 encoded query
    encoded_query = urllib.parse.quote(base64_query, safe="")

    return f"https://portal.azure.com#@{tenant_id}/blade/Microsoft_OperationsManagementSuite_Workspace/Logs.ReactView/resourceId/%2Fsubscriptions%2F{subscription_id}%2Fresourcegroups%2F{resource_group_name}%2Fproviders%2Fmicrosoft.operationalinsights%2Fworkspaces%2F{workspace_name}/source/LogsBlade.AnalyticsShareLinkToQuery/q/{encoded_query}"


class QueryProcessor:
    """
    This is a class to run queries against Log Analytics.
    """

    def __init__(
        self,
        workspace_id: str,
        token_credential: TokenCredential,
        tenant_id: str | None = None,
        subscription_id: str | None = None,
        resource_group_name: str | None = None,
        workspace_name: str | None = None,
        app_insights_name: str | None = None,
    ) -> None:
        """
        Constructor

        Parameters:
            workspace_id (str): Workspace ID
            api_key (str): API Key
            token_credential (TokenCredential): TokenCredential object
            tenant_id (str): Tenant ID (required if outputting links to the Azure Portal)
            subscription_id (str): Subscription ID (required if outputting links to the Azure Portal)
            resource_group_name (str): Resource Group Name (required if outputting links to the Azure Portal)
            workspace_name (str): Workspace Name (required if outputting links to the Azure Portal)
            app_insights_name (str): App Insights Name (required if outputting links to the Azure Portal)
        """
        if workspace_id is None:
            raise ValueError("workspace_id is required")
        self.__workspace_id = workspace_id
        self.__queries = []
        self.__tenant_id = tenant_id
        self.__subscription_id = subscription_id
        self.__resource_group_name = resource_group_name
        self.__logs_query_client = LogsQueryClient(token_credential)
        self.__workspace_name = workspace_name
        self.__app_insights_name = app_insights_name

    def add_query(
        self,
        title,
        query,
        validation_func=None,
        timespan="PT12H",
        is_chart=False,
        columns=[],
        group_definition: GroupDefinition | None = None,
        chart_config=dict(),
        show_query=False,
        include_link=False,
    ):
        """
        Adds a query to be executed.

        Parameters:
            title (str): Title of the query to be run (describes behaviour)
            query (str): Application Insights query to be run in Kusto query language (KQL).
            validation_func: The function that validates the results of a query.
            timespan (str): The time period into the past from now to fetch data to query on for.
                            in format PT<TIME DURATION> e.g. PT12H.
            is_chart (bool): If true then a chart is rendered else a table.
            columns (list(str)): Columns to render in the chart as series.
            group_definition (GroupDefinition): Grouping definition for the query result.
            chart_config (dict): Asciichart graph config, info can be found here: https://github.com/kroitor/asciichart.
            show_query (bool): If true then the query is printed before the result.
            include_link (bool): If true then a link to the query in the Azure Portal is printed. Requires tenant, subscription, resource group  and app insights name to be set
        """

        self.__queries.append(
            (
                title,
                query,
                validation_func,
                timespan,
                is_chart,
                columns,
                chart_config,
                group_definition,
                show_query,
                include_link,
            )
        )

    def run_queries(self):
        """
        Runs queries stored in __queries and prints result to stdout.
        """
        query_error_count = 0
        for query_index, (
            title,
            query,
            validation_func,
            timespan,
            is_chart,
            columns,
            chart_config,
            group_definition,
            show_query,
            include_link,
        ) in enumerate(self.__queries):
            print()
            print(f"Running query {query_index + 1} of {len(self.__queries)}")
            print(f"{asciichart.yellow}{title}{asciichart.reset}")
            if show_query:
                print(query)
                print("")
            if include_link:
                url = get_log_analytics_portal_url(
                    self.__tenant_id,
                    self.__subscription_id,
                    self.__resource_group_name,
                    self.__workspace_name,
                    query,
                )
                link = get_link("Run in Log Analytics", url)
                print(link)
                print("")
            result, error_message = self.run_query(query, timespan)

            if error_message:
                print()
                print(f"Query '{title}' failed with error: {error_message}")
                query_error_count += 1
                continue

            if group_definition:
                if columns and len(columns) > 0:
                    raise ValueError(
                        "Cannot specify columns when using group_definition"
                    )
                result = result.group_by(
                    group_definition.id_column,
                    group_definition.group_column,
                    group_definition.value_column,
                    group_definition.missing_value,
                )
                columns = [
                    col
                    for col in result.columns
                    if col.startswith(group_definition.value_column + "_")
                ]
                columns = sorted(columns)

            if is_chart:
                self.__output_chart(result, title, columns, chart_config)
            else:
                self.__output_table(result, title)

            # Validate result
            if validation_func:
                validation_error = validation_func(result)
                if validation_error:
                    print(
                        f"{asciichart.red}Query '{title}' failed with validation error: {validation_error}{asciichart.reset}"
                    )
                    query_error_count += 1
                    continue

            print()

        return query_error_count

    def run_query(self, query, timespan) -> tuple[Table, str]:
        """
        Runs a query on a given timespan.

        Parameters:
            query (str): Query in Kusto query language (KQL) to run.
            timespan (str): The time period into the past from now to fetch data to query on for.
                            in format PT<TIME DURATION> e.g. PT12H.

        Returns:
            Table with results
            Error code if any.
        """

        try:
            response = self.__logs_query_client.query_workspace(
                workspace_id=self.__workspace_id,
                query=query,
                timespan=timespan,
            )
        except HttpResponseError as e:
            return None, e.message

        table = response.tables[0]
        rows = table.rows
        columns = table.columns
        return Table(columns=columns, rows=rows), None

    def wait_for_non_zero_count(self, query, max_retries=10, wait_time_seconds=30):
        """
        Run a query until it returns a non-zero count.
        """
        for _ in range(max_retries):
            r, _ = self.run_query(
                query=query,
                timespan=(datetime.now(UTC) - timedelta(days=1), datetime.now(UTC)),
            )
            count = r.rows[0][0]
            if count > 0:
                logging.info("✔️ Found metrics data")
                return
            logging.info("⏳ Waiting for metrics data...")
            time.sleep(wait_time_seconds)

        raise Exception("❌ No metrics data found")

    def build_token_metric_url(self, start_time, end_time): 
        """
        Run a query until it returns a non-zero count.
        """
        link = get_log_analytics_token_metric_url(
            self.__tenant_id,
            self.__subscription_id,
            self.__resource_group_name,
            self.__app_insights_name,
            start_time,
            end_time
        )
        print(link)
        print("")
    

    def __output_table(self, query_result: Table, title):
        """
        Outputs the result of the ran query in table format.

        Parameters:
            query_result (Table): the result of the ran query.
            title: the title of the query ran which describes its behaviour.
        """
        print(tabulate(query_result.rows, query_result.columns))

    def __output_chart(self, query_result: Table, title, columns, config=dict()):
        """
        Outputs the result of the ran query in chart format.

        Parameters:
            query_result (Table): the result of the ran query.
            title: the title of the query ran which describes its behaviour.
            columns: Columns of the query result to display as a series in the chart.
            config: The style configuration for the chart, info can be found here: https://github.com/kroitor/asciichart.
        """

        def get_column_values(table: Table, column: str):
            try:
                column_index = table.columns.index(column)
            except ValueError:
                raise ValueError(
                    f"Column '{column}' not found in table columns: "
                    + ",".join(table.columns)
                )
            return [row[column_index] for row in table.rows]

        series = [get_column_values(query_result, column) for column in columns]
        print(asciichart.plot(series, config))