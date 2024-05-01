# Usage tracking using Azure Event Hub

## Scenario

In this setup, you can track the usage of your APIs by sending token usage data to Azure Event Hub. Message sent to event hub includes, SubscriptionId, TokenUsage, OperationName, RequestId.

## How the policy works

- Azure OpenAI response will contain the token usage data. This policy extracts the token usage data from the response and sends it to Azure Event Hub.
- This policy fragment needs to be included in the `outbound` section of the APIM policy.

### Caveats

- This policy only applies to non-streaming requests.
