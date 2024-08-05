# Prioritization - Simple

## Capability

In this capability we have different priorities of request (high and low).
High priority requests should always be allowed through to the backend, whie low priority requests should be allowed through only if there is sufficient spare capacity remaining.

## How the policy works

The general flow for the prioritization policy is as follows:
1. The policy checks the priority of the request. Low priority requests are identified by either an `priority` query parameter or an `x-priority` header with a value of `low`.
2. If the request is a low priority request, the policy checks if there is sufficient available capacity to allow the request through.
3. If there is sufficient spare capacity, the request is allowed through to the backend. Otherwise it is rejected with a 429 response.
4. When a response is received from the backend, the policy retrieves the `x-ratelimit-remaining-tokens` and `x-ratelimit-remaining-requests` headers and stores this in the API Management cache. These values are used to determine availablt capacity the when the next request is received

***TODO - comparison to token-counting implementation***
- lag in simple implementation when rate-limited from backend (especially when no high-priority requests are processed)
- complexity/maintenance cost


### Prioritization configuration

The first step of the prioritization processing is determining the level of spare capacity to reserve for a given deployment.
This is achieved by setting a `low-priority-tpm-threshold` and `low-priority-rp10s-threshold` value for each deployment to set the number of tokens and requests respectively that should be available for a low priority request to be processed.

```xml
<cache-lookup-value key="list-deployments" variable-name="list-deployments" />
<choose>
	<when condition="@(context.Variables.ContainsKey("list-deployments") == false)">
		<set-variable name="list-deployments" value="@{
			JArray deployments = new JArray();
			deployments.Add(new JObject()
			{
				{ "deployment-id", "embedding100k" },
				// embedding100k has a 100,000 TPM limit
				// Set low-priority-tpm-threshold to 30,000 to reserve 30,000 TPM for high priority requests
				// 100,000 TPM  = 6/1000 * 100,000 = 600 RPM
				//              = 10 RP10S (requests per 10 seconds)
				{ "low-priority-tpm-threshold", 30000},
				{ "low-priority-rp10s-threshold", 3},
			});
			deployments.Add(new JObject()
			{
				{ "deployment-id", "embedding" },
				{ "low-priority-tpm-threshold", 3000},
				{ "low-priority-rp10s-threshold", 3},
			});
			deployments.Add(new JObject()
			{
				{ "deployment-id", "gpt-35-turbo-10k-token" },
				{ "low-priority-tpm-threshold", 3000},
				{ "low-priority-rp10s-threshold", 3},
			});
			deployments.Add(new JObject()
			{
				{ "deployment-id", "gpt-35-turbo-20k-token" },
				{ "low-priority-tpm-threshold", 3000},
				{ "low-priority-rp10s-threshold", 3},
			});
			return deployments;   
		}" />
		<cache-store-value key="list-deployments" value="@((JArray)context.Variables["list-deployments"])" duration="60" />
	</when>
</choose>
```

Once the deployment configuration is retrieved, the values for the current request are determined using the deployment ID from the request path.


***TODO - finish doc!***
