#!/bin/bash
set -e

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"


# Reset the latencies (get the endpoints and call config)

output_generated_keys="$script_dir/../../../infra/apim-genai/generated-keys.json"
output_simulators="$script_dir/../../../infra/apim-genai/output-simulators.json"

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



echo "Config for PAYG1 ($payg1_base_url)"
curl -s \
	--request PATCH \
	--url "$payg1_base_url/++/config" \
	--header "api-key: $simulator_api_key" \
	--header 'content-type: application/json' \
	--data '{"latency": {"open_ai_completions": {"mean": 20}}}' | jq
echo ""
echo "Config for PAYG2 ($payg2_base_url)"
curl -s \
	--request PATCH \
	--url "$payg2_base_url/++/config" \
	--header "api-key: $simulator_api_key" \
	--header 'content-type: application/json' \
	--data '{"latency": {"open_ai_completions": {"mean": 10}}}' | jq