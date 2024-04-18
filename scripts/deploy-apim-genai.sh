#!/bin/bash
set -e

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

if [[ -f "$script_dir/../.env" ]]; then
	echo "Loading .env"
	source "$script_dir/../.env"
fi

if [[ ${#PTU_DEPLOYMENT_1_BASE_URL} -eq 0 ]]; then
  echo 'ERROR: Missing environment variable PTU_DEPLOYMENT_1_BASE_URL' 1>&2
  exit 6
else
  PTU_DEPLOYMENT_1_BASE_URL="${PTU_DEPLOYMENT_1_BASE_URL%$'\r'}"
fi

if [[ ${#PAYG_DEPLOYMENT_1_BASE_URL} -eq 0 ]]; then
  echo 'ERROR: Missing environment variable PAYG_DEPLOYMENT_1_BASE_URL' 1>&2
  exit 6
else
  PAYG_DEPLOYMENT_1_BASE_URL="${PAYG_DEPLOYMENT_1_BASE_URL%$'\r'}"  
fi

if [[ ${#PAYG_DEPLOYMENT_2_BASE_URL} -eq 0 ]]; then
  echo 'ERROR: Missing environment variable PAYG_DEPLOYMENT_2_BASE_URL' 1>&2
  exit 6
else
  PAYG_DEPLOYMENT_2_BASE_URL="${PAYG_DEPLOYMENT_2_BASE_URL%$'\r'}"  
fi

RESOURCE_GROUP_NAME=$(jq -r ".apimResourceGroupName" "$script_dir/../infra/apim-baseline/output.json")
API_MANAGEMENT_SERVICE_NAME=$(jq -r ".apimName" "$script_dir/../infra/apim-baseline/output.json")

cat << EOF > "$script_dir/../infra/apim-genai/azuredeploy.parameters.json"
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "apiManagementServiceName" :{ 
        "value": "${API_MANAGEMENT_SERVICE_NAME}"
    },
    "ptuDeploymentOneBaseUrl": {
        "value": "${PAYG_DEPLOYMENT_1_BASE_URL}"
    },
    "payAsYouGoDeploymentOneBaseUrl": {
        "value": "${PAYG_DEPLOYMENT_1_BASE_URL}"
    },
    "payAsYouGoDeploymentTwoBaseUrl": {
        "value": "${PAYG_DEPLOYMENT_2_BASE_URL}"
    }
  }
}
EOF

deployment_name="deployment-${RESOURCE_NAME_PREFIX}-genai"

echo "$deployment_name"
cd  "$script_dir/../infra/apim-genai"
echo "=="
echo "== Starting bicep deployment ${deployment_name}"
echo "=="
output=$(az deployment group create \
  --template-file main.bicep \
  --name "$deployment_name" \
  --parameters azuredeploy.parameters.json \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --output json)
echo "$output" | jq "[.properties.outputs | to_entries | .[] | {key:.key, value: .value.value}] | from_entries" > "$script_dir/../infra/apim-genai/output.json"
echo -e "\n"

echo "Bicep deployment completed"