#!/bin/bash
set -e

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

if [[ -f "$script_dir/../.env" ]]; then
	echo "Loading .env"
	source "$script_dir/../.env"
fi

cd "$script_dir/../infra/simulators"

if [[ ${#AZURE_LOCATION} -eq 0 ]]; then
  echo 'ERROR: Missing environment variable AZURE_LOCATION' 1>&2
  exit 6
else
  AZURE_LOCATION="${AZURE_LOCATION%$'\r'}"
fi

if [[ ${#RESOURCE_NAME_PREFIX} -eq 0 ]]; then
  echo 'ERROR: Missing environment variable RESOURCE_NAME_PREFIX' 1>&2
  exit 6
else
  RESOURCE_NAME_PREFIX="${RESOURCE_NAME_PREFIX%$'\r'}"  
fi

if [[ ${#ENVIRONMENT_TAG} -eq 0 ]]; then
  echo 'ERROR: Missing environment variable ENVIRONMENT_TAG' 1>&2
  exit 6
else
  ENVIRONMENT_TAG="${ENVIRONMENT_TAG%$'\r'}"  
fi

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

build_image() {
    local simulator_path=$1
    local acr_name=$2
    local acr_login_server=$3
    local image_tag=$4

    src_path=$(realpath "$simulator_path/src/aoai-api-simulator")

    # create a tik_token_cache folder to avoid failure in the build
    mkdir -p "$src_path/tiktoken_cache"

    az acr login --name "$acr_name"
    az acr build --image "${acr_login_server}/aoai-api-simulator:$image_tag" --registry "$acr_name" --file "$src_path/Dockerfile" "$src_path"
    
    echo -e "\n"
}

#
# This script uses a number of files to store generated keys and outputs from the deployment:
# - generated-keys.json: stores generated keys (e.g. API Key for the API simulator)
# - output-simulator-base.json: stores the output from the base simulator deployment (e.g. container registry details)
# - output-simulators.json: stores the output from the simulator instances deployment (e.g. simulator endpoints)
# - output.json: stores the output from the main deployment (e.g. APIM endpoints)
#

output_generated_keys="$script_dir/../infra/simulators/generated-keys.json"
output_simulator_base="$script_dir/../infra/simulators/output-simulator-base.json"
output_simulators="$script_dir/../infra/simulators/output-simulators.json"
output_genai_base="$script_dir/../infra/apim-genai/output-genai-base.json"

# Ensure output-keys.json exists and add empty JSON object if not
if [[ ! -f "$output_generated_keys" ]]; then
  echo "{}" > "$output_generated_keys"
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
  simulator_git_tag=${SIMULATOR_GIT_TAG:=v0.5}

  if [[ -n "$SIMULATOR_IMAGE_TAG" ]]; then
    simulator_image_tag=$SIMULATOR_IMAGE_TAG
  else
    simulator_image_tag=$simulator_git_tag
  fi
  simulator_image_tag=${simulator_image_tag//\//_} # Replace slashes with underscores
  echo "Using simulator git tag: $simulator_git_tag"
  echo "Using simulator image tag: $simulator_image_tag"
  
  clone_simulator=true
  if [[ -d "$simulator_path" ]]; then
    if [[ -f "$script_dir/.simulator_tag" ]]; then
      previous_tag=$(cat "$script_dir/.simulator_tag")
      if [[ "$previous_tag" == "$simulator_git_tag" ]]; then
        clone_simulator=false
        echo "Simulator folder already exists - skipping clone."
      else
        rm -rf "$simulator_path"
        echo "Cloned simulator has tag ${previous_tag} - re-cloning ${simulator_git_tag}."
      fi
    else
        rm -rf "$simulator_path"
        echo "Cloned simulator exists without tag file - re-cloning ${simulator_git_tag}."
    fi
  else
    echo "Simulator folder does not exist - cloning."
  fi

  if [[ "$clone_simulator" == "true" ]]; then
    echo "Cloning simulator (tag: ${simulator_git_tag})..."
    git clone \
      --depth 1 \
      --branch "$simulator_git_tag" \
      --config advice.detachedHead=false \
      https://github.com/microsoft/aoai-api-simulator \
      "$simulator_path"
    echo "$simulator_git_tag" > "$script_dir/.simulator_tag"
  fi

  #
  # Deploy simulator base resources
  #
  user_id=$(az ad signed-in-user show --output tsv --query id)

cat << EOF > "$script_dir/../infra/simulators/azuredeploy.parameters.json"
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
    "location": {
      "value": "${AZURE_LOCATION}"
    },
    "additionalKeyVaulSecretReaderPrincipalId": {
      "value": "${user_id}"
    }
  }
}
EOF

  deployment_name="sim-base-${RESOURCE_NAME_PREFIX}"

  echo -e "\n=="
  echo "== Starting bicep deployment ${deployment_name}"
  echo "=="
  output=$(az deployment sub create \
    --location "$AZURE_LOCATION" \
    --template-file base.bicep \
    --name "$deployment_name" \
    --parameters azuredeploy.parameters.json \
    --output json)

  echo "== Completed bicep deployment ${deployment_name}"

  echo "$output" | jq "[.properties.outputs | to_entries | .[] | {key:.key, value: .value.value}] | from_entries" > "$output_simulator_base"


  resource_group_name=$(jq -r '.resourceGroupName // ""' < "$output_simulator_base")
  app_insights_name=$(jq -r '.appInsightsName // ""' < "$output_simulator_base")
  log_analytics_name=$(jq -r '.logAnalyticsName // ""' < "$output_simulator_base")

  if [[ -z "$resource_group_name" ]]; then
    echo "Resource group name (resourceGroupName) not found in output-simulator-base.json"
    exit 1
  fi

  if [[ -z "$app_insights_name" ]]; then
    echo "App Insights name (appInsightsName) not found in output-simulator-base.json"
    exit 1
  fi

  if [[ -z "$log_analytics_name" ]]; then
    echo "Log Analytics name (logAnalyticsName) not found in output-simulator-base.json"
    exit 1
  fi

  # if app insights key not stored, create and store
  app_insights_key=$(jq -r '.appInsightsKey // ""' < "$output_generated_keys")
  if [[ ${#app_insights_key} -eq 0 ]]; then
    echo 'Creating app insights key'
    app_insights_key=$(az monitor app-insights api-key create  --resource-group "$resource_group_name" --app "$app_insights_name" --api-key automation --query 'apiKey' --output tsv)
    jq ".appInsightsKey = \"${app_insights_key}\"" < "$output_generated_keys" > "/tmp/generated-keys.json"
    cp "/tmp/generated-keys.json" "$output_generated_keys"
  fi

  #
  # Build and push docker image
  #
  echo "Building simulator docker image..."
  acr_login_server=$(jq -r '.containerRegistryLoginServer // ""' < "$output_simulator_base")
  if [[ -z "$acr_login_server" ]]; then
    echo "Container registry login server not found in output-simulator-base.json"
    exit 1
  fi
  acr_name=$(jq -r '.containerRegistryName // ""' < "$output_simulator_base")
  if [[ -z "$acr_name" ]]; then
    echo "Container registry name not found in output-simulator-base.json"
    exit 1
  fi

  set +e
  existing_image=$(az acr repository show-tags --name "$acr_name" --repository "aoai-api-simulator" -o tsv --query "contains(@, '${simulator_image_tag}')" 2>&1)
  set -e

  if [[ "$existing_image" == "true" ]]; then
    if [[ "${FORCE_SIMULATOR_BUILD}" != "true" ]]; then
      echo "Simulator docker image previously pushed with tag $simulator_image_tag. Skipping build."
    else
      echo "Simulator docker image previously pushed. Forcing build."
      build_image "$simulator_path" "$acr_name" "$acr_login_server" "$simulator_image_tag"
    fi
  else
    echo "No simulator docker image previously pushed with tag $simulator_image_tag. Building."
    build_image "$simulator_path" "$acr_name" "$acr_login_server" "$simulator_image_tag"
  fi
  
  #
  # Deploy simulator instances
  #
  key_vault_name=$(jq -r '.keyVaultName // ""' < "$output_simulator_base")
  if [[ -z "$key_vault_name" ]]; then
    echo "Key vault name (keyVaultName) not found in output-simulator-base.json"
    exit 1
  fi
  container_app_env_name=$(jq -r '.containerAppEnvName // ""' < "$output_simulator_base")
  if [[ -z "$container_app_env_name" ]]; then
    echo "Container app env name (containerAppEnvName) not found in output-simulator-base.json"
    exit 1
  fi

cat << EOF > "$script_dir/../infra/simulators/azuredeploy.parameters.json"
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "resourceGroupName" : {
      "value": "${resource_group_name}"
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
    "simulatorImageTag": {
      "value": "${simulator_image_tag}"
    },
    "keyVaultName": {
      "value": "${key_vault_name}"
    },
    "appInsightsName": {
      "value": "${app_insights_name}"
    }
  }
}
EOF

  deployment_name="sims-${RESOURCE_NAME_PREFIX}"

  echo -e "\n=="
  echo "== Starting bicep deployment ${deployment_name}"
  echo "=="
  output=$(az deployment sub create \
    --location "$AZURE_LOCATION" \
    --template-file simulators.bicep \
    --name "$deployment_name" \
    --parameters azuredeploy.parameters.json \
    --output json)

  echo "== Completed bicep deployment ${deployment_name}"

  echo "$output" | jq "[.properties.outputs | to_entries | .[] | {key:.key, value: .value.value}] | from_entries" > "$output_simulators"

  #
  # Get simulator endpoints to use in APIM deployment
  #
  ptu1_fqdn=$(jq -r '.ptu1Fqdn // ""' < "$output_simulators")
  if [[ -z "${ptu1_fqdn}" ]]; then
    echo "PTU1 Endpoint not found in simulator deployment output"
    exit 1
  fi
  PTU_DEPLOYMENT_1_BASE_URL="https://${ptu1_fqdn}"
  
  payg1_fqdn=$(jq -r '.payg1Fqdn // ""' < "$output_simulators")
  if [[ -z "${payg1_fqdn}" ]]; then
    echo "PAYG1 Endpoint not found in simulator deployment output"
    exit 1
  fi
  PAYG_DEPLOYMENT_1_BASE_URL="https://${payg1_fqdn}"

  payg2_fqdn=$(jq -r '.payg2Fqdn // ""' < "$output_simulators")
  if [[ -z "${payg2_fqdn}" ]]; then
    echo "PAYG2 Endpoint not found in simulator deployment output"
    exit 1
  fi
  PAYG_DEPLOYMENT_2_BASE_URL="https://${payg2_fqdn}"

  ptu_deployment_1_api_key=$SIMULATOR_API_KEY
  payg_deployment_1_api_key=$SIMULATOR_API_KEY
  payg_deployment_2_api_key=$SIMULATOR_API_KEY

else

  cd "$script_dir/../infra/apim-genai"

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
    "location": {
      "value": "${AZURE_LOCATION}"
    },
  }
}
EOF

  deployment_name="genai-base-${RESOURCE_NAME_PREFIX}"

  echo -e "\n=="
  echo "== Starting bicep deployment ${deployment_name}"
  echo "=="
  output=$(az deployment sub create \
    --location "$AZURE_LOCATION" \
    --template-file base.bicep \
    --name "$deployment_name" \
    --parameters azuredeploy.parameters.json \
    --output json)

  echo "== Completed bicep deployment ${deployment_name}"

  echo "$output" | jq "[.properties.outputs | to_entries | .[] | {key:.key, value: .value.value}] | from_entries" > "$output_genai_base"

  resource_group_name=$(jq -r '.resourceGroupName // ""' < "$output_genai_base")
  app_insights_name=$(jq -r '.appInsightsName // ""' < "$output_genai_base")
  log_analytics_name=$(jq -r '.logAnalyticsName // ""' < "$output_genai_base")

  if [[ -z "$resource_group_name" ]]; then
    echo "Resource group name (resourceGroupName) not found in output-genai-base.json"
    exit 1
  fi

  if [[ -z "$app_insights_name" ]]; then
    echo "App Insights name (appInsightsName) not found in output-genai-base.json"
    exit 1
  fi

  if [[ -z "$log_analytics_name" ]]; then
    echo "Log Analytics name (logAnalyticsName) not found in output-genai-base.json"
    exit 1
  fi

  if [[ ${#PTU_DEPLOYMENT_1_API_KEY} -eq 0 ]]; then
    echo 'ERROR: Missing environment variable PTU_DEPLOYMENT_1_API_KEY' 1>&2
    exit 6
  else
    PTU_DEPLOYMENT_1_API_KEY="${PTU_DEPLOYMENT_1_API_KEY%$'\r'}"
  fi

  if [[ ${#PAYG_DEPLOYMENT_1_API_KEY} -eq 0 ]]; then
    echo 'ERROR: Missing environment variable PAYG_DEPLOYMENT_1_API_KEY' 1>&2
    exit 6
  else
    PAYG_DEPLOYMENT_1_API_KEY="${PAYG_DEPLOYMENT_1_API_KEY%$'\r'}"  
  fi

  if [[ ${#PAYG_DEPLOYMENT_2_API_KEY} -eq 0 ]]; then
    echo 'ERROR: Missing environment variable PAYG_DEPLOYMENT_2_API_KEY' 1>&2
    exit 6
  else
    PAYG_DEPLOYMENT_2_API_KEY="${PAYG_DEPLOYMENT_2_API_KEY%$'\r'}"  
  fi

  ptu_deployment_1_api_key=$PTU_DEPLOYMENT_1_API_KEY
  payg_deployment_1_api_key=$PAYG_DEPLOYMENT_1_API_KEY
  payg_deployment_2_api_key=$PAYG_DEPLOYMENT_2_API_KEY

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

cd "$script_dir/../infra/apim-genai"

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
    "ptuDeploymentOneBaseUrl": {
        "value": "${PTU_DEPLOYMENT_1_BASE_URL}"
    },
    "ptuDeploymentOneApiKey": {
        "value": "${ptu_deployment_1_api_key}"
    },
    "payAsYouGoDeploymentOneBaseUrl": {
        "value": "${PAYG_DEPLOYMENT_1_BASE_URL}"
    },
    "payAsYouGoDeploymentOneApiKey": {
        "value": "${payg_deployment_1_api_key}"
    },
    "payAsYouGoDeploymentTwoBaseUrl": {
        "value": "${PAYG_DEPLOYMENT_2_BASE_URL}"
    },
    "payAsYouGoDeploymentTwoApiKey": {
        "value": "${payg_deployment_2_api_key}"
    },
    "logAnalyticsName": {
        "value": "${log_analytics_name}"
    },
    "appInsightsName": {
        "value": "${app_insights_name}"
    }
  }
}
EOF

deployment_name="genai-${RESOURCE_NAME_PREFIX}"

echo -e "\n=="
echo "== Starting bicep deployment ${deployment_name}"
echo "=="
output=$(az deployment group create \
  --template-file main.bicep \
  --name "$deployment_name" \
  --parameters azuredeploy.parameters.json \
  --resource-group "$resource_group_name" \
  --output json)
  
echo "== Completed bicep deployment ${deployment_name}"

echo "$output" | jq "[.properties.outputs | to_entries | .[] | {key:.key, value: .value.value}] | from_entries" > "$script_dir/../infra/apim-genai/output.json"

echo -e "\n"