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

### Policy Fragments

- The repository contains policies in the format of [Policy fragments](https://learn.microsoft.com/en-us/azure/api-management/policy-fragments)
- You can manually [create these fragments](https://learn.microsoft.com/en-us/azure/api-management/policy-fragments#create-a-policy-fragment) in your APIM instance and can refer them in the corresponding API operations.

### Managed Identity between APIM and Azure OpenAI

These examples use Managed Identity to authenticate between APIM and Azure OpenAI. [Follow these 3 steps](https://learn.microsoft.com/en-us/azure/api-management/api-management-authenticate-authorize-azure-openai#authenticate-with-managed-identity) to setup the Managed identity between APIM and Azure OpenAI

## Policies




