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

## Policies

## Deployment

The repository contains Bicep files ([/infra](./infra/)) and associated scripts ([/scripts](./scripts/)) that deploy GenAI Gateway infrastructure to Azure.

First, sign in with the Azure CLI:

```bash
az login
```

Next, deploy the infrastructure, passing in a unique string for `--username` (used in resource names) and an Azure Region for `--location`:

```bash
./scripts/deploy-bicep.sh --username "{USERNAME}" --location "{AZURE_REGION}"
```
