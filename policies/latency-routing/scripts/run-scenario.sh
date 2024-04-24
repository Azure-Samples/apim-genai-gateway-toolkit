#!/bin/bash
set -e

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"


# Reset the latencies (get the endpoints and call config)

output_generated_keys="$script_dir/../../../infra/apim-genai/generated-keys.json"
output_simulator_base="$script_dir/../../../infra/apim-genai/output-simulator-base.json"
output_simulators="$script_dir/../../../infra/apim-genai/output-simulators.json"
output_main="$script_dir/../../../infra/apim-genai/output.json"

payg1_fqdn=$(cat "$output_simulators"  | jq -r '.payg1Fqdn // ""')
if [[ -z "${payg1_fqdn}" ]]; then
echo "PAYG1 Endpoint not found in simulator deployment output"
exit 1
fi
payg1_base_url="https://${payg1_fqdn}"

payg2_fqdn=$(cat "$output_simulators"  | jq -r '.payg2Fqdn // ""')
if [[ -z "${payg2_fqdn}" ]]; then
echo "PAYG2 Endpoint not found in simulator deployment output"
exit 1
fi
payg2_base_url="https://${payg2_fqdn}"

simulator_api_key=$(cat "$output_generated_keys"  | jq -r '.simulatorApiKey // ""')
if [[ -z "${payg2_fqdn}" ]]; then
	echo "Simulator API Key not found in generated keys file"
	exit 1
fi

apim_key=$(cat "$output_main"  | jq -r '.apiManagementAzureOpenAIProductSubscriptionKey // ""')
if [[ -z "${apim_key}" ]]; then
	echo "APIM Key not found in deployment output file"
	exit 1
fi
key_vault_name=$(cat "$output_simulator_base"  | jq -r '.keyVaultName // ""')
if [[ -z "${key_vault_name}" ]]; then
	echo "Key Vault Name not found in output.json"
	exit 1
fi
app_insights_connection_string=$(az keyvault secret show --vault-name "$key_vault_name" --name app-insights-connection-string-ptu1 --query value --output tsv)
if [[ -z "${app_insights_connection_string}" ]]; then
	echo "App Insights Connection String not found in Key Vault"
	exit 1
fi

apim_name=$(cat "$output_main"  | jq -r '.apiManagementName // ""')
if [[ -z "${apim_name}" ]]; then
	echo "APIM Name not found in output.json"
	exit 1
fi
apim_base_url="https://${apim_name}.azure-api.net"

# Run the locust test (set user count and duration and gather the results)

# NOTES:
# --users arg includes 1 for the orchestrator user
# --autoquit arg is the time to wait after the run is complete before quitting (allow 30s to flush app insights metrics)
APIM_KEY=$apim_key \
APIM_ENDPOINT=$apim_base_url \
APP_INSIGHTS_CONNECTION_STRING=$app_insights_connection_string \
SIMULATOR_ENDPOINT_PAYG1=$payg1_base_url \
SIMULATOR_ENDPOINT_PAYG2=$payg2_base_url \
SIMULATOR_API_KEY=$simulator_api_key \
OTEL_SERVICE_NAME=locust \
OTEL_METRIC_EXPORT_INTERVAL=10000 \
LOCUST_WEB_PORT=8091 \
locust \
	-f ./policies/latency-routing/scripts/load_injectors.py \
	-H "$apim_base_url/latency-routing/" \
	--users 2 \
	--run-time 4m30s \
	--autostart \
	--autoquit 30



# TODO Get the results and print them

# TODO - stretch: wait and then query the metrics??