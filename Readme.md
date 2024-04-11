# GenAI Gateway Accelerator using APIM

## GenAI Gateway

A "GenAI gateway" serves as an intelligent interface/middleware that dynamically balances incoming traffic across backend resources to achieve optimizing resource utilization. In addition to load balancing, GenAI Gateway can be equipped with extra capabilities to address the challenges around billing, monitoring etc.

Read more about [GenAI gateway](https://learn.microsoft.com/en-us/ai/playbook/technology-guidance/generative-ai/genai-gateway/)

## Accelerator

The aim of this accelerator is to provide a quick start for deploying a GenAI Gateway using Azure API Management (APIM). The accelerator contains

- Policies
- Code to deploy APIM

## Prerequisites

- Azure Subscription
- Azure CLI

### Policy Fragments

- The repository contains policies in the format of [Policy fragments](https://learn.microsoft.com/en-us/azure/api-management/policy-fragments)
- You can manually [create these fragments](https://learn.microsoft.com/en-us/azure/api-management/policy-fragments#create-a-policy-fragment) in your APIM instance and can refer them in the corresponding API operations.

### Managed Identity between APIM and Azure OpenAI

These examples use Managed Identity to authenticate between APIM and Azure OpenAI. [Follow these 3 steps](https://learn.microsoft.com/en-us/azure/api-management/api-management-authenticate-authorize-azure-openai#authenticate-with-managed-identity) to setup the Managed identity between APIM and Azure OpenAI

## Policies

## Deployment

The repository contains Bicep files ([/infra](./infra/)) and associated scripts ([/scripts](./scripts/)) that deploy GenAI Gateway infrastructure to Azure.

First, sign in with the Azure CLI:

```bash
az login
```

Next, deploy the infrastructure, passing in a unique string for `--username` (used in resource names), an Azure Region for `--location`, the base name of the policy fragment file to test, and the base urls for the various real or simulated Azure Open AI Service endpoints:

```bash
./scripts/deploy-bicep.sh --username "{USERNAME}" --location "{AZURE_REGION}" --ptuEndpoint1 "{PTU_DEPLOYMENT_1_BASE_URL}" --paygEndpoint1 "{PAYG_DEPLOYMENT_1_BASE_URL}" --paygEndpoint2 "{PAYG_DEPLOYMENT_2_BASE_URL}" --policyFragment "{POLICY_FRAGMENT_FILE_NAME}"
```
