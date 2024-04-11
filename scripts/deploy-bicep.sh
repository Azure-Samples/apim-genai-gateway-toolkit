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
      echo "    --policyFragment, -f      : REQUIRED: Name of the policy fragment to test"
      echo "    --ptuEndpoint1, -x        : REQUIRED: Base url of first AOAI PTU deployment"
      echo "    --paygEndpoint1, -y       : REQUIRED: Base url of first AOAI PAYG deployment"
      echo "    --paygEndpoint2, -z       : REQUIRED: Base url of second AOAI PAYG deployment"
      echo ""
      exit 1
}

SHORT=u:,l:,f:,x:,y:,z:,h
LONG=username:,location:,policyFragment:,ptuEndpoint1:,paygEndpoint1:,paygEndpoint2:,help
OPTS=$(getopt -a -n files --options $SHORT --longoptions $LONG -- "$@")

eval set -- "$OPTS"

USERNAME=''
LOCATION=''
POLICYFRAGMENT=''
PTUENDPOINT1=''
PAYGENDPOINT1=''
PAYGENDPOINT2=''

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
    -f | --policyFragment )
      POLICYFRAGMENT="$2"
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

if [[ ${#POLICYFRAGMENT} -eq 0 ]]; then
  echo 'ERROR: Missing required parameter --policyFragment | -f' 1>&2
  exit 6
fi

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
    "policyFragment": {
      "value": "${POLICYFRAGMENT}"
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