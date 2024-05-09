# API Management (APIM) GenAI Gateway Toolkit

- [API Management (APIM) GenAI Gateway Toolkit](#api-management-apim-genai-gateway-toolkit)
	- [Introduction](#introduction)
	- [Getting Started](#getting-started)
		- [Using Visual Studio Code Dev Containers](#using-visual-studio-code-dev-containers)
		- [Prerequisites for non Dev Container setup](#prerequisites-for-non-dev-container-setup)
	- [Deploying the Accelerator](#deploying-the-accelerator)
	- [Gateway Capabilities](#gateway-capabilities)
	- [Testing Gateway Capabilities](#testing-gateway-capabilities)

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

Once that is done, open the repository in Visual Studio Code and select `Dev Containers: Reopen in Container` from the command palette.
This will create an environment with all the pre-requisites installed.

NOTE: When the container is built Visual Studio Code will automatically install the python dependencies required for the end-to-end capability tests. If you pull a later version of the code, you make need to run `pip install -r end_to_end_tests/requirements.txt` to install the dependencies (or rebuild the dev container).

### Prerequisites for non Dev Container setup

If you are manually installing the pre-requisites, you will need the following:

- Azure CLI
  - including the `application-insights` extension (`az extension add --name  application-insights`)
- Docker (if using the OpenAI API simulator)
- Python 3 (to run end-to-end tests)
- `jq` (to parse JSON responses in bash scripts)
- a bash terminal (see [Windows Subsystem for Linux](https://learn.microsoft.com/en-us/windows/wsl/install) if you are on Windows)
- Install python dependencies for the end-to-end tests by running `pip install -r end_to_end_tests/requirements.txt`

## Deploying the Accelerator

To see the GenAI Gateway capabilities in action, you can deploy the infrastructure using the provided Bicep templates. The infrastructure is deployed in two steps to match the [APIM Landing Zone Accelerator](https://github.com/Azure/apim-landing-zone-accelerator/blob/feat-apim-v2/scenarios/scripts/deploy-apim-baseline.sh) - the first is responsible for deploying the baseline API Management service while the second adds configuration details to the service that enable those capabilities.  

1. The templates require parameters set via an .env file and the project contains a [`sample.env`](./sample.env) with the required environment variables. Rename `sample.env` to `.env` and set the values accordingly.

2. Sign in with the Azure CLI:

```bash
az login
```

3. Deploy the baseline infrastructure:

```bash
./scripts/deploy-apim-baseline.sh
```

4. Deploy the GenAI-specific configuration details to API Management:

```bash
./scripts/deploy-apim-genai.sh
```

> **_NOTE:_**  A known KV/ACA bug requires the `deploy-apim-genai.sh` script to be run twice.

## Gateway Capabilities

This repo currently contains the policies showing how to implement these GenAI Gateway capabilities:

| Capability                                                                      | Description                                                             |
| ------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| [Latency based routing](./capabilities/latency-routing/README.md) | Route traffic to the endpoint with the lowest latency. |
| [Load balancing (round-robin)](./capabilities/load-balancing-round-robin/Readme.md) | Load balance traffic across PAYG endpoints using round-robin algorithm. |
| [Managing spikes with PAYG](./capabilities/manage-spikes-with-payg/README.md) | Manage spikes in traffic by routing traffic to PAYG endpoints when a PTU is out of capacity. |
| [Adaptive rate limiting](./capabilities/rate-limiting/README.md) | Dynamically adjust rate-limits applied to different workloads|
| [Tracking token usage](./capabilities/usage-tracking//README.md) | Record the token consumption for usage tracking and attribution|

## Testing Gateway Capabilities

The easiest way to see the gateway capabilities in action is to deploy the gateway along with the OpenAI API Simualtor (set the `USE_SIMULATOR` option in your `.env` file to `true`).

Once you have the gateway and simulator deployed, see the `README.md` in the relevant capability folder for instructions on how to test the capability. (NOTE: currently not all capabilities have tests implemented)
