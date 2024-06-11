# Token based rate limiting

## Capability

In this capability, callers are differentiated into high and low priority buckets and are rate limited based on token usage. Callers start with default limits, but rates are dynamically increased within a set maximum depending on spare capacity and type of caller.

## How the policy works

The `azure-openai-token-limit` policy in Azure API Management (APIM) is a powerful tool for controlling access to your APIs based on the number of tokens consumed. Here's a step-by-step breakdown of how it operates:

- The policy extracts the token consumption data from the response and increments the corresponding rate limit counters. These counters track the usage of resources and enforce the defined rate limits.
- A global rate limit is set to the maximum overall rate. With each request, its counter increases based on the tokens consumed. It resets at regular intervals, typically every 60 seconds, ensuring that the rate limits are enforced consistently over time.
- Alongside the global limit, dynamic local limits (high and low priority requests are determined by headers) are used with different default values. These counters are adjusted based on the availability of the global rate limit counter. If there's spare capacity due to low usage by other services, these local counters can increase within a set maximum threshold, allowing services to temporarily access more resources.
- Prompt tokens are pre-calculated by APIM so requests are automatically rate limited without sending unnecessary requests to the AOAI simulators.