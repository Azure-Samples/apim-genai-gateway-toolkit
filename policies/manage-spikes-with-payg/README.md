# Manage spikes of PTU usage with Pay-As-You-Go (PAYG) endpoints

## Pre-requisites

- Authentication between APIM and Azure OpenAI backends using Managed Identity, should have been done.
- Named value pairs for the backend endpoints should have been created in APIM. In this example, the named value pairs are `ptu-endpoint-1` `payg-endpoint-1` and `payg-endpoint-2` with the values as the backend endpoints.

## How to use this

- [Create a policy fragment in APIM](https://learn.microsoft.com/en-us/azure/api-management/policy-fragments#create-a-policy-fragment) with the content of `retry-with-payg.xml`
- Update the list of backends in the policy fragment with the named value pairs created in the pre-requisites.
- Refer the fragment in the corresponding API operation in the `backend` section of the policy.

## How it works

- The policy fragment `retry-with-payg.xml` manages the PTU spikes with PAYG endpoints.
- By default the request is routed to a PTU endpoint (or a pool of PTU endpoints).
- If the PTU endpoint returns a 429 status code, the request is retried with a PAYG endpoint (or a pool of PAYG endpoints)

## Impact

This will help in managing the usage spikes of the consumer application, and will help in reducing the upfront cost to procure higher PTU capacity.
