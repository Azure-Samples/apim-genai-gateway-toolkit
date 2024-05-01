#!/bin/bash
set -e

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

if [[ -f "$script_dir/../.env" ]]; then
	echo "Loading .env"
	source "$script_dir/../.env"
fi

cd "$script_dir/../infra/apim-genai"

if [[ "${USE_SIMULATOR}" != "true" ]]; then
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
fi


#
# This script uses a number of files to store generated keys and outputs from the deployment:
# - generated-keys.json: stores generated keys (e.g. API Key for the API simulator)
# - output-simulator-base.json: stores the output from the base simulator deployment (e.g. container registry details)
# - output-simulators.json: stores the output from the simulator instances deployment (e.g. simulator endpoints)
# - output.json: stores the output from the main deployment (e.g. APIM endpoints)
#

RESOURCE_GROUP_NAME=$(jq -r '.apimResourceGroupName // ""' < "$script_dir/../infra/apim-baseline/output.json")
API_MANAGEMENT_SERVICE_NAME=$(jq -r '.apimName // ""' < "$script_dir/../infra/apim-baseline/output.json")

output_generated_keys="$script_dir/../infra/apim-genai/generated-keys.json"
output_simulator_base="$script_dir/../infra/apim-genai/output-simulator-base.json"
output_simulators="$script_dir/../infra/apim-genai/output-simulators.json"
output_base="$script_dir/../infra/apim-baseline/output.json"

# Ensure output-keys.json exists and add empty JSON object if not
if [[ ! -f "$output_generated_keys" ]]; then
  echo "{}" > "$output_generated_keys"
fi

app_insights_name=$(jq -r '.appInsightsName // ""' < "$output_base")
if [[ -z "$app_insights_name" ]]; then
  echo "App Insights name (appInsightsName) not found in output-base.json"
  exit 1
fi
log_analytics_name=$(jq -r '.logAnalyticsName // ""' < "$output_base")
if [[ -z "$log_analytics_name" ]]; then
  echo "Log Analytics name (logAnalyticsName) not found in output-base.json"
  exit 1
fi


if [[ "${USE_SIMULATOR}" == "true" ]]; then
  echo "Using OpenAI API Simulator"

  
  # if key passed, use and write out
  # if key not passed, load from file and generate if not present
  if [[ ${#SIMULATOR_API_KEY} -eq 0 ]]; then
    SIMULATOR_API_KEY=$(jq -r '.simulatorApiKey // ""' < "$output_generated_keys")
    if [[ ${#SIMULATOR_API_KEY} -eq 0 ]]; then
      echo 'SIMULATOR_API_KEY not set and no stored value found - generating key'
      SIMULATOR_API_KEY=$(bash "$script_dir/utils/generate-api-key.sh")
    else
      echo "Loaded SIMULATOR_API_KEY from generated-keys.json"
    fi
    jq ".simulatorApiKey = \"${SIMULATOR_API_KEY}\"" < "$output_generated_keys" > "/tmp/generated-keys.json"
    cp "/tmp/generated-keys.json" "$output_generated_keys"
  fi

  #
  # Clone simulator
  #
  simulator_path="$script_dir/simulator"
  simulator_tag=${SIMULATOR_GIT_TAG:=v0.2}
  if [[ -d "$simulator_path" ]]; then
    echo "Simulator folder already exists - skipping clone."
  else
    echo "Cloning simulator (tag: ${simulator_tag})..."
    git clone \
      --depth 1 \
      --branch $simulator_tag \
      --config advice.detachedHead=false \
      https://github.com/stuartleeks/aoai-simulated-api \
      "$simulator_path"
  fi


  #
  # Deploy simulator base resources
  #

  user_id=$(az ad signed-in-user show --output tsv --query id)

cat << EOF > "$script_dir/../infra/apim-genai/azuredeploy.parameters.json"
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "resourceGroupName" : {
      "value": "${RESOURCE_GROUP_NAME}"
    },
    "workloadName" :{ 
        "value": "${RESOURCE_NAME_PREFIX}"
    },
    "environment" :{ 
        "value": "${ENVIRONMENT_TAG}"
    },
    "location": {
      "value": "${AZURE_LOCATION}"
    },
    "additionalKeyVaulSecretReaderPrincipalId": {
      "value": "${user_id}"
    },
    "logAnalyticsName": {
      "value": "${log_analytics_name}"
    }
  }
}
EOF
  echo "Simulator base bicep parameters file created"

  deployment_name="deployment-${RESOURCE_NAME_PREFIX}-sim-base"
  echo "Simulator base bicep deployment ($deployment_name) starting..."
  az deployment sub create \
    --location "$AZURE_LOCATION" \
    --template-file base.bicep \
    --name "$deployment_name" \
    --parameters azuredeploy.parameters.json \
    --output json \
    | jq "[.properties.outputs | to_entries | .[] | {key:.key, value: .value.value}] | from_entries" > $output_simulator_base
  if [[ "$(cat $output_simulator_base)" == "" ]]; then
    echo "Simulator base bicep deployment ($deployment_name) failed"
    exit 6
  fi

  # if app insights key not stored, create and store
  app_insights_key=$(jq -r '.appInsightsKey // ""' < "$output_generated_keys")
  if [[ ${#app_insights_key} -eq 0 ]]; then
    echo 'Creating app insights key'
    app_insights_key=$(az monitor app-insights api-key create  --resource-group $RESOURCE_GROUP_NAME --app $app_insights_name --api-key automation --query 'apiKey' --output tsv)
    jq ".appInsightsKey = \"${app_insights_key}\"" < "$output_generated_keys" > "/tmp/generated-keys.json"
    cp "/tmp/generated-keys.json" "$output_generated_keys"
  fi

  #
  # Build and push docker image
  #
  echo "Building simulator docker image..."
  acr_login_server=$(cat $output_simulator_base  | jq -r '.containerRegistryLoginServer // ""')
  if [[ -z "$acr_login_server" ]]; then
    echo "Container registry login server not found in output-simulator-base.json"
    exit 1
  fi
  acr_name=$(cat $output_simulator_base  | jq -r '.containerRegistryName // ""')
  if [[ -z "$acr_name" ]]; then
    echo "Container registry name not found in output-simulator-base.json"
    exit 1
  fi

  src_path=$(realpath "$simulator_path/src/aoai-simulated-api")

# create a tik_token_cache folder to avoid failure in the build
  mkdir -p "$src_path/tiktoken_cache"

  az acr login --name $acr_name
  az acr build --image ${acr_login_server}/aoai-simulated-api:latest --registry $acr_name --file "$src_path/Dockerfile" "$src_path"
  
  echo -e "\n"

  
  #
  # Upload simulator deployment config files to file share
  #
  echo "Uploading simulator config files to file share..."
  storage_account_name=$(cat $output_simulator_base  | jq -r '.storageAccountName // ""')
  if [[ -z "$storage_account_name" ]]; then
    echo "Storage account name (storageAccountName) not found in output-simulator-base.json"
    exit 1
  fi

  file_share_name=$(cat $output_simulator_base  | jq -r '.fileShareName // ""')
  if [[ -z "$file_share_name" ]]; then
    echo "File share name (fileShareName) not found in output-simulator-base.json"
    exit 1
  fi

  storage_key=$(az storage account keys list --account-name "$storage_account_name" -o tsv --query '[0].value')

  az storage file upload-batch --destination "$file_share_name" --source "$script_dir/../infra/apim-genai/simulator_file_content" --account-name "$storage_account_name" --account-key "$storage_key"

  #
  # Deploy simulator instances
  #

  key_vault_name=$(cat $output_simulator_base  | jq -r '.keyVaultName // ""')
  if [[ -z "$key_vault_name" ]]; then
    echo "Key vault name (keyVaultName) not found in output-simulator-base.json"
    exit 1
  fi
  container_app_env_name=$(cat $output_simulator_base  | jq -r '.containerAppEnvName // ""')
  if [[ -z "$container_app_env_name" ]]; then
    echo "Container app env name (containerAppEnvName) not found in output-simulator-base.json"
    exit 1
  fi

cat << EOF > "$script_dir/../infra/apim-genai/azuredeploy.parameters.json"
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "resourceGroupName" : {
      "value": "${RESOURCE_GROUP_NAME}"
    },
    "workloadName" :{ 
        "value": "${RESOURCE_NAME_PREFIX}"
    },
    "environment" :{ 
        "value": "${ENVIRONMENT_TAG}"
    },
    "location": {
      "value": "${AZURE_LOCATION}"
    },
    "simulatorApiKey": {
      "value": "${SIMULATOR_API_KEY}"
    },
    "containerAppEnvName": {
      "value": "${container_app_env_name}"
    },
    "containerRegistryName": {
      "value": "${acr_name}"
    },
    "keyVaultName": {
      "value": "${key_vault_name}"
    },
    "storageAccountName": {
      "value": "${storage_account_name}"
    },
    "appInsightsName": {
      "value": "${app_insights_name}"
    }
  }
}
EOF
  echo "Simulators bicep parameters file created"

  cd "$script_dir/../infra/apim-genai"

  deployment_name="deployment-${RESOURCE_NAME_PREFIX}-sims"
  echo "Simulator base bicep deployment ($deployment_name) starting..."
  az deployment sub create \
    --location "$AZURE_LOCATION" \
    --template-file simulators.bicep \
    --name "$deployment_name" \
    --parameters azuredeploy.parameters.json \
    --output json \
    | jq "[.properties.outputs | to_entries | .[] | {key:.key, value: .value.value}] | from_entries" > "$output_simulators"
    if [[ "$(cat $output_simulator_base)" == "" ]]; then
      echo "Simulators bicep deployment ($deployment_name) failed"
      exit 6
    fi
  echo "Simulators bicep deployment ($deployment_name) completed"

  #
  # Get simulator endpoints to use in APIM deployment
  #
  ptu1_fqdn=$(cat "$output_simulators"  | jq -r '.ptu1Fqdn // ""')
  if [[ -z "${ptu1_fqdn}" ]]; then
    echo "PTU1 Endpoint not found in simulator deployment output"
    exit 1
  fi
  PTU_DEPLOYMENT_1_BASE_URL="https://${ptu1_fqdn}"
  
  payg1_fqdn=$(cat "$output_simulators"  | jq -r '.payg1Fqdn // ""')
  if [[ -z "${payg1_fqdn}" ]]; then
    echo "PAYG1 Endpoint not found in simulator deployment output"
    exit 1
  fi
  PAYG_DEPLOYMENT_1_BASE_URL="https://${payg1_fqdn}"

  payg2_fqdn=$(cat "$output_simulators"  | jq -r '.payg2Fqdn // ""')
  if [[ -z "${payg2_fqdn}" ]]; then
    echo "PAYG2 Endpoint not found in simulator deployment output"
    exit 1
  fi
  PAYG_DEPLOYMENT_2_BASE_URL="https://${payg2_fqdn}"

fi

#
# Ensure that the base urls end with /openai (TODO - do we want to enforce this here? or in the APIM config for the back-ends?)
#
if [[ "${PTU_DEPLOYMENT_1_BASE_URL: -7}" != "/openai" ]]; then
    PTU_DEPLOYMENT_1_BASE_URL="${PTU_DEPLOYMENT_1_BASE_URL}/openai"
fi
if [[ "${PAYG_DEPLOYMENT_1_BASE_URL: -7}" != "/openai" ]]; then
    PAYG_DEPLOYMENT_1_BASE_URL="${PAYG_DEPLOYMENT_1_BASE_URL}/openai"
fi
if [[ "${PAYG_DEPLOYMENT_2_BASE_URL: -7}" != "/openai" ]]; then
    PAYG_DEPLOYMENT_2_BASE_URL="${PAYG_DEPLOYMENT_2_BASE_URL}/openai"
fi


#
# Deploy APIM policies etc
#

cat << EOF > "$script_dir/../infra/apim-genai/azuredeploy.parameters.json"
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "workloadName" :{ 
        "value": "${RESOURCE_NAME_PREFIX}"
    },
    "environment" :{ 
        "value": "${ENVIRONMENT_TAG}"
    },
    "apiManagementServiceName" :{ 
        "value": "${API_MANAGEMENT_SERVICE_NAME}"
    },
    "ptuDeploymentOneBaseUrl": {
        "value": "${PTU_DEPLOYMENT_1_BASE_URL}"
    },
    "ptuDeploymentOneApiKey": {
        "value": "${SIMULATOR_API_KEY}"
    },
    "payAsYouGoDeploymentOneBaseUrl": {
        "value": "${PAYG_DEPLOYMENT_1_BASE_URL}"
    },
    "payAsYouGoDeploymentOneApiKey": {
        "value": "${SIMULATOR_API_KEY}"
    },
    "payAsYouGoDeploymentTwoBaseUrl": {
        "value": "${PAYG_DEPLOYMENT_2_BASE_URL}"
    },
    "payAsYouGoDeploymentTwoApiKey": {
        "value": "${SIMULATOR_API_KEY}"
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