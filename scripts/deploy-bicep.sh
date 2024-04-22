#!/bin/bash
set -e

#
# This script generates the bicep parameters file and then uses that to deploy the infrastructure
# An output.json file is generated in the project root containing the outputs from the deployment
#

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

help()
{
    echo ""
    echo "<This command will deploy the whole required infrastructure for this project by using Bicep>"
    echo ""
    echo "Command"
    echo "    deploy-bicep.sh : Will deploy all required services services."
    echo ""
    echo "Arguments"
    echo "    --username, -u            : REQUIRED: Unique name to assign in all deployed services, your high school hotmail alias is a great idea!"
    echo "    --location, -l            : REQUIRED: Azure region to deploy to"
    echo "    --ptuEndpoint1, -x        : Base url of first AOAI PTU deployment (required if --use-simulator is not set)"
    echo "    --paygEndpoint1, -y       : Base url of first AOAI PAYG deployment (required if --use-simulator is not set)"
    echo "    --paygEndpoint2, -z       : Base url of second AOAI PAYG deployment (required if --use-simulator is not set)"
    echo "    --use-simulator           : Use simulated AOAI endpoints"
    echo "    --simulator-api-key,      : API key to use for calling the simulator (if blank a key will be generated and stored in generated-keys.json)"
    echo ""
    exit 1
}

SHORT=u:,l:,x:,y:,z:,h
LONG=username:,location:,ptuEndpoint1:,paygEndpoint1:,paygEndpoint2:,use-simulator,simulator-api-key:,help
OPTS=$(getopt -a -n files --options $SHORT --longoptions $LONG -- "$@")

eval set -- "$OPTS"

USERNAME=''
LOCATION=''
PTUENDPOINT1=''
PAYGENDPOINT1=''
PAYGENDPOINT2=''
USE_SIMULATOR=0

while :
do
  case "$1" in
    -u | --username )
      USERNAME="$2"
      shift 2
      ;;
    -l | --location )
      LOCATION="$2"
      shift 2
      ;;
    -x | --ptuEndpoint1 )
      PTUENDPOINT1="$2"
      shift 2
      ;;
    -y | --paygEndpoint1 )
      PAYGENDPOINT1="$2"
      shift 2
      ;;
    -z | --paygEndpoint2 )
      PAYGENDPOINT2="$2"
      shift 2
      ;;
    --use-simulator )
      USE_SIMULATOR=1
      shift 1
      ;;
    --simulator-api-key )
      SIMULATOR_API_KEY="$2"
      shift 2
      ;;
    -h | --help)
      help
      ;;
    --)
      shift;
      break
      ;;
    *)
      echo "Unexpected option: $1"
      ;;
  esac
done

if [[ ${#USERNAME} -eq 0 ]]; then
  echo 'ERROR: Missing required parameter --username | -u' 1>&2
  exit 6
fi

if [[ ${#LOCATION} -eq 0 ]]; then
  echo 'ERROR: Missing required parameter --location | -l' 1>&2
  exit 6
fi
if [[ ${USE_SIMULATOR} -eq 0 ]]; then
  if [[ ${#PTUENDPOINT1} -eq 0 ]]; then
    echo 'ERROR: Missing required parameter --ptuEndpoint1 | -x' 1>&2
    exit 6
  fi

  if [[ ${#PAYGENDPOINT1} -eq 0 ]]; then
    echo 'ERROR: Missing required parameter --paygEndpoint1 | -y' 1>&2
    exit 6
  fi

  if [[ ${#PAYGENDPOINT2} -eq 0 ]]; then
    echo 'ERROR: Missing required parameter --paygEndpoint2 | -z' 1>&2
    exit 6
  fi
fi

#
# This script uses a number of files to store generated keys and outputs from the deployment:
# - generated-keys.json: stores generated keys (e.g. API Key for the API simulator)
# - output-simulator-base.json: stores the output from the base simulator deployment (e.g. container registry details)
# - output-simulators.json: stores the output from the simulator instances deployment (e.g. simulator endpoints)
# - output.json: stores the output from the main deployment (e.g. APIM endpoints)
#


# Ensure output-keys.json exists and add empty JSON object if not
if [[ ! -f "$script_dir/../generated-keys.json" ]]; then
  echo "{}" > "$script_dir/../generated-keys.json"
fi


if [[ ${USE_SIMULATOR} -eq 1 ]]; then
  echo "Using OpenAI API Simulator"
  
  # if key passed, use and write out
  # if key not passed, load from file and generate if not present
  if [[ ${#SIMULATOR_API_KEY} -eq 0 ]]; then
    SIMULATOR_API_KEY=$(jq -r .simulatorApiKey < "$script_dir/../generated-keys.json")
    if [[ "${SIMULATOR_API_KEY}" == "null" ]] || [[ ${#SIMULATOR_API_KEY} -eq 0 ]]; then
      echo 'SIMULATOR_API_KEY not set and no stored value found - generating key'
      SIMULATOR_API_KEY=$(bash "$script_dir/generate-api-key.sh")
    else
      echo "Loaded SIMULATOR_API_KEY from generated-keys.json"
    fi
    jq ".simulatorApiKey = \"${SIMULATOR_API_KEY}\"" < "$script_dir/../generated-keys.json" > "/tmp/generated-keys.json"
    cp "/tmp/generated-keys.json" "$script_dir/../generated-keys.json"
  fi

  #
  # Clone simulator
  #
  simulator_path="$script_dir/simulator"
  simulator_tag=v0.1
  if [[ -d "$simulator_path" ]]; then
    echo "Simulator folder already exists - skipping clone."
  else
    echo "Cloning simulator..."
    git clone \
      --depth 1 \
      --branch $simulator_tag \
      --config advice.detachedHead=false \
      https://github.com/stuartleeks/aoai-simulated-api \
      "$simulator_path"
    echo -e "\n*\n" > "$simulator_path/.gitignore"
  fi

  #
  # Deploy simulator base resources
  #

  cd "$script_dir/../infra/"
cat << EOF > "$script_dir/../infra/azuredeploy.parameters.json"
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "${LOCATION}"
    },
    "uniqueUserName": {
      "value": "${USERNAME}"
    }
  }
}
EOF
  echo "Simulator base bicep parameters file created"

  deployment_name="deployment-${USERNAME}-${LOCATION}"
  echo "Simulator base bicep deployment ($deployment_name) starting..."
  az deployment sub create \
    --location "$LOCATION" \
    --template-file base.bicep \
    --name "$deployment_name" \
    --parameters azuredeploy.parameters.json \
    --output json \
    | jq "[.properties.outputs | to_entries | .[] | {key:.key, value: .value.value}] | from_entries" > "$script_dir/../output-simulator-base.json"

  echo "Simulator base bicep deployment ($deployment_name) starting..."

  #
  # Build and push docker image
  #
  echo "Building simulator docker image..."
  acr_login_server=$(cat "$script_dir/../output-simulator-base.json"  | jq -r .containerRegistryLoginServer)
  if [[ -z "$acr_login_server" ]]; then
    echo "Container registry login server not found in output.json"
    exit 1
  fi
  acr_name=$(cat "$script_dir/../output-simulator-base.json"  | jq -r .containerRegistryName)
  if [[ -z "$acr_name" ]]; then
    echo "Container registry name not found in output.json"
    exit 1
  fi

  src_path=$(realpath "$simulator_path/src/aoai-simulated-api")

  docker build -t ${acr_login_server}/aoai-simulated-api:latest "$src_path" -f "$src_path/Dockerfile"

  az acr login --name $acr_name
  docker push ${acr_login_server}/aoai-simulated-api:latest

  echo -e "\n"

  
  #
  # Upload simulator deployment config files to file share
  #
  echo "Uploading simulator config files to file share..."
  storage_account_name=$(cat $script_dir/../output-simulator-base.json  | jq -r .storageAccountName)
  if [[ -z "$storage_account_name" ]]; then
    echo "Storage account name (storageAccountName) not found in output-simulator-base.json"
    exit 1
  fi

  file_share_name=$(cat $script_dir/../output-simulator-base.json  | jq -r .fileShareName)
  if [[ -z "$file_share_name" ]]; then
    echo "File share name (fileShareName) not found in output-simulator-base.json"
    exit 1
  fi

  storage_key=$(az storage account keys list --account-name "$storage_account_name" -o tsv --query '[0].value')

  az storage file upload-batch --destination "$file_share_name" --source "$script_dir/../infra/simulator_file_content" --account-name "$storage_account_name" --account-key "$storage_key"

  #
  # Deploy simulator instances
  #

  cd "$script_dir/../infra/"
cat << EOF > "$script_dir/../infra/azuredeploy.parameters.json"
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "${LOCATION}"
    },
    "uniqueUserName": {
      "value": "${USERNAME}"
    },
    "simulatorApiKey": {
      "value": "${SIMULATOR_API_KEY}"
    }
  }
}
EOF
  echo "Simulators  bicep parameters file created"

  cd "$script_dir/../infra/"

  deployment_name="deployment-${USERNAME}-${LOCATION}"
  echo "Simulator base bicep deployment ($deployment_name) starting..."
  az deployment sub create \
    --location "$LOCATION" \
    --template-file simulators.bicep \
    --name "$deployment_name" \
    --parameters azuredeploy.parameters.json \
    --output json \
    | jq "[.properties.outputs | to_entries | .[] | {key:.key, value: .value.value}] | from_entries" > "$script_dir/../output-simulators.json"

  echo "Simulator base bicep deployment ($deployment_name) completed"

  #
  # Get simulator endpoints to use in APIM deployment
  #
  ptu1_fqdn=$(cat "$script_dir/../output-simulators.json"  | jq -r .ptu1_fqdn)
  if [[ -z "${ptu1_fqdn}" ]]; then
    echo "PTU1 Endpoint not found in simulator deployment output"
    exit 1
  fi
  PTUENDPOINT1="https://${ptu1_fqdn}"
  
  payg1_fqdn=$(cat "$script_dir/../output-simulators.json"  | jq -r .payg1_fqdn)
  if [[ -z "${payg1_fqdn}" ]]; then
    echo "PAYG1 Endpoint not found in simulator deployment output"
    exit 1
  fi
  PAYGENDPOINT1="https://${payg1_fqdn}"

  payg2_fqdn=$(cat "$script_dir/../output-simulators.json"  | jq -r .payg2_fqdn)
  if [[ -z "${payg2_fqdn}" ]]; then
    echo "PAYG2 Endpoint not found in simulator deployment output"
    exit 1
  fi
  PAYGENDPOINT2="https://${payg2_fqdn}"

fi


#
# Deploy APIM, policies etc
#

# TODO - pass endpoint api keys here
cat << EOF > "$script_dir/../infra/azuredeploy.parameters.json"
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "${LOCATION}"
    },
    "uniqueUserName": {
      "value": "${USERNAME}"
    },
    "ptuDeploymentOneBaseUrl": {
      "value": "${PTUENDPOINT1}"
    },
    "payAsYouGoDeploymentOneBaseUrl": {
      "value": "${PAYGENDPOINT1}"
    },
    "payAsYouGoDeploymentTwoBaseUrl": {
      "value": "${PAYGENDPOINT2}"
    }
  }
}
EOF

echo "Bicep parameters file created"

cd "$script_dir/../infra/"

deployment_name="deployment-${USERNAME}-${LOCATION}"
echo "Starting Bicep deployment ($deployment_name)"
az deployment sub create \
  --location "$LOCATION" \
  --template-file main.bicep \
  --name "$deployment_name" \
  --parameters azuredeploy.parameters.json \
  --output json \
  | jq "[.properties.outputs | to_entries | .[] | {key:.key, value: .value.value}] | from_entries" > "$script_dir/../output.json"

echo "Bicep deployment completed"