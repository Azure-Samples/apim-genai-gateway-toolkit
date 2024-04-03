# Manage spikes of PTU usage with Pay-As-You-Go (PAYG) endpoints

## Pre-requisites

- Authentication between APIM and Azure OpenAI backends using Managed Identity, should have been done.
- Named value pairs for the backend endpoints should have been created in APIM. In this example, the named value pairs are `ptu-endpoint-1` `payg-endpoint-1` and `payg-endpoint-2` with the values as the backend endpoints.

## How to use this

- [Create a policy fragment in APIM](https://learn.microsoft.com/en-us/azure/api-management/policy-fragments#create-a-policy-fragment) with the content of `retry-with-payg.xml`
- Update the list of backends in the policy fragment with the named value pairs created in the pre-requisites.
- Refer the fragment in the corresponding API operation in the `inbound` section of the policy.