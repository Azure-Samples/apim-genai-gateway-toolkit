# GenAI Gateway Accelerator using API Management (APIM)

- [GenAI Gateway Accelerator using API Management (APIM)](#genai-gateway-accelerator-using-api-management-apim)
	- [Introduction](#introduction)
	- [Getting Started](#getting-started)
		- [Using Visual Studio Code Dev Containers](#using-visual-studio-code-dev-containers)
		- [Prerequisites](#prerequisites)
	- [Deploying the Accelerator](#deploying-the-accelerator)
		- [Managed Identity between APIM and Azure OpenAI](#managed-identity-between-apim-and-azure-openai)
	- [Testing Accelerator Capabilities](#testing-accelerator-capabilities)
		- [Policy Fragments](#policy-fragments)
	- [Gateway Capabilities](#gateway-capabilities)


## Introduction

The aim of this accelerator is to provide a quick start for deploying a GenAI Gateway using Azure API Management (APIM). 

A "GenAI Gateway" serves as an intelligent interface/middleware that dynamically balances incoming traffic across backend resources to achieve optimizing resource utilization. In addition to load balancing, GenAI Gateway can be equipped with extra capabilities to address the challenges around billing, monitoring etc.

To read more about considerations when implementing a GenAI Gateway, see [this article](https://learn.microsoft.com/ai/playbook/technology-guidance/generative-ai/dev-starters/genai-gateway/).

This accelerator contains APIM policies showing how to implement different [GenAI Gateway capabilities](#gateway-capabilities) in APIM, along with code to enable you to deploy the policies and see them in action.

## Getting Started

To see the policies in action you need to set up your environment (you will need an Azure Subscription to deploy into).

For this you can either install the [pre-requisites](#prerequisites) on your local machine or use the [Visual Studio Code Dev Containers](#using-visual-studio-code-dev-containers) to set up the environment.

### Using Visual Studio Code Dev Containers

Follow the [Dev Containers Getting Started Guide](https://code.visualstudio.com/docs/devcontainers/containers) to set up Visual Studio Code for using Dev Containers.

Once that is done, open the repository in Visual Studio Code and select `Dev Containers: Reopen in Container` from the command palette. This will create an environment with all the pre-requisites installed.

### Prerequisites

If you are manually installing the pre-requisites, you will need the following:

- Azure CLI
- Docker (if using the OpenAI API simulator)
- a bash terminal (see [Windows Subsystem for Linux](https://learn.microsoft.com/en-us/windows/wsl/install) if you are on Windows)


## Deploying the Accelerator

To see the GenAI Gateway capabilities in action, you can deploy the infrastructure using the provided Bicep templates.

First, sign in with the Azure CLI:

```bash
az login
```

Next, deploy the infrastructure, passing in a unique string for `--username` (used in resource names), an Azure Region for `--location`, the base name of the policy fragment file to test, and the base urls for the various real or simulated Azure Open AI Service endpoints:

```bash
./scripts/deploy-bicep.sh --username "{USERNAME}" --location "{AZURE_REGION}" --ptuEndpoint1 "{PTU_DEPLOYMENT_1_BASE_URL}" --paygEndpoint1 "{PAYG_DEPLOYMENT_1_BASE_URL}" --paygEndpoint2 "{PAYG_DEPLOYMENT_2_BASE_URL}" --policyFragment "{POLICY_FRAGMENT_FILE_NAME}"
```

### Managed Identity between APIM and Azure OpenAI

These examples use Managed Identity to authenticate between APIM and Azure OpenAI. [Follow these 3 steps](https://learn.microsoft.com/en-us/azure/api-management/api-management-authenticate-authorize-azure-openai#authenticate-with-managed-identity) to setup the Managed identity between APIM and Azure OpenAI

## Testing Accelerator Capabilities

TODO - Add instructions on how to test 

### Policy Fragments

- The repository contains policies in the format of [Policy fragments](https://learn.microsoft.com/en-us/azure/api-management/policy-fragments)
- You can manually [create these fragments](https://learn.microsoft.com/en-us/azure/api-management/policy-fragments#create-a-policy-fragment) in your APIM instance and can refer them in the corresponding API operations.


## Gateway Capabilities

This repo currently contains the policies showing how to implement these GenAI Gateway capabilities:

| Capability                                                                      | Description                                                             |
| ------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| [Load balancing (round-robin)](./policies/load-balancing-round-robin/Readme.md) | Load balance traffic across PAYG endpoints using round-robin algorithm. |

