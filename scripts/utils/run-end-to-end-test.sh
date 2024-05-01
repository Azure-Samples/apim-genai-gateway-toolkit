#!/bin/bash
set -e

#
# This is a helper script for running the secenario tests
#

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

if [[ -z "${RUN_TIME}" ]]; then
	echo "RUN_TIME not set!"
	exit 1
fi
if [[ -z "${USER_COUNT}" ]]; then
	echo "USER_COUNT not set!"
	exit 1
fi
if [[ -z "${SCENARIO_NAME}" ]]; then
	echo "SCENARIO_NAME not set!"
	exit 1
fi

if [[ "${SCENARIO_NAME}" == "latency-routing" ]]; then
	test_file="scenario_latency_routing.py"
	host_endpoint_path="latency-routing"
elif [[ "${SCENARIO_NAME}" == "round-robin-simple" ]]; then
	test_file="scenario_round_robin.py"
	host_endpoint_path="round-robin-simple"
elif [[ "${SCENARIO_NAME}" == "round-robin-weighted" ]]; then
	test_file="scenario_round_robin.py"
	host_endpoint_path="round-robin-weighted"
else
	echo "Unknown scenario name: ${SCENARIO_NAME}"
	exit 1
fi

output_generated_keys="$script_dir/../../infra/apim-genai/generated-keys.json"
output_simulator_base="$script_dir/../../infra/apim-genai/output-simulator-base.json"
output_simulators="$script_dir/../../infra/apim-genai/output-simulators.json"
output_main="$script_dir/../../infra/apim-genai/output.json"

payg1_fqdn=$(jq -r '.payg1Fqdn // ""' < "$output_simulators")
if [[ -z "${payg1_fqdn}" ]]; then
echo "PAYG1 Endpoint not found in simulator deployment output"
exit 1
fi
payg1_base_url="https://${payg1_fqdn}"

payg2_fqdn=$(jq -r '.payg2Fqdn // ""' < "$output_simulators")
if [[ -z "${payg2_fqdn}" ]]; then
echo "PAYG2 Endpoint not found in simulator deployment output"
exit 1
fi
payg2_base_url="https://${payg2_fqdn}"


resource_group_name=$(jq -r '.resourceGroupName // ""'< "$output_simulators")
if [[ -z "${resource_group_name}" ]]; then
	echo "Resource Group Name not found in output-simulators.json"
	exit 1
fi

simulator_api_key=$(jq -r '.simulatorApiKey // ""'< "$output_generated_keys")
if [[ -z "${payg2_fqdn}" ]]; then
	echo "Simulator API Key not found in generated keys file"
	exit 1
fi

app_insights_name=$(jq -r '.appInsightsName // ""'< "$output_simulator_base")
if [[ -z "${app_insights_name}" ]]; then
	echo "App Insights Name not found in output.json"
	exit 1
fi

key_vault_name=$(jq -r '.keyVaultName // ""'< "$output_simulator_base")
if [[ -z "${key_vault_name}" ]]; then
	echo "Key Vault Name not found in output.json"
	exit 1
fi
app_insights_connection_string=$(az keyvault secret show --vault-name "$key_vault_name" --name app-insights-connection-string-ptu1 --query value --output tsv)
if [[ -z "${app_insights_connection_string}" ]]; then
	echo "App Insights Connection String not found in Key Vault"
	exit 1
fi

apim_key=$(jq -r '.apiManagementAzureOpenAIProductSubscriptionKey // ""'< "$output_main")
if [[ -z "${apim_key}" ]]; then
	echo "APIM Key not found in deployment output file"
	exit 1
fi

apim_name=$(cat "$output_main"  | jq -r '.apiManagementName // ""')
if [[ -z "${apim_name}" ]]; then
	echo "APIM Name not found in output.json"
	exit 1
fi
apim_base_url="https://${apim_name}.azure-api.net"


subscription_id=$(az account show --output tsv --query id)
tenant_id=$(az account show --output tsv --query tenantId)

# Run the locust test (set user count and duration and gather the results)

load_test_root="$script_dir/../../end_to_end_tests"

APIM_KEY=$apim_key \
APIM_ENDPOINT=$apim_base_url \
APP_INSIGHTS_NAME=$app_insights_name \
TENANT_ID=$tenant_id \
SUBSCRIPTION_ID=$subscription_id \
RESOURCE_GROUP_NAME=$resource_group_name \
APP_INSIGHTS_CONNECTION_STRING=$app_insights_connection_string \
SIMULATOR_ENDPOINT_PAYG1=$payg1_base_url \
SIMULATOR_ENDPOINT_PAYG2=$payg2_base_url \
SIMULATOR_API_KEY=$simulator_api_key \
OTEL_SERVICE_NAME=locust \
OTEL_METRIC_EXPORT_INTERVAL=10000 \
LOCUST_WEB_PORT=8091 \
locust \
	-f "$load_test_root/$test_file" \
	-H "$apim_base_url/$host_endpoint_path/" \
	--users "$USER_COUNT" \
	--run-time "$RUN_TIME" \
	--autostart \
	--autoquit 0
