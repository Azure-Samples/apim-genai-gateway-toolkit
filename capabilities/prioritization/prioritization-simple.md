# Prioritization - Simple

- [Prioritization - Simple](#prioritization---simple)
	- [Capability](#capability)
	- [How to see this in action](#how-to-see-this-in-action)
	- [How the policy works](#how-the-policy-works)
		- [Prioritization configuration](#prioritization-configuration)
		- [Managing low-priority only requests](#managing-low-priority-only-requests)


## Capability

In this capability we have different priorities of request (high and low).
High priority requests should always be allowed through to the backend, while low priority requests should be allowed through only if there is sufficient spare capacity remaining.

For details of how this implementation compares to the other implementations, see the the [main prioritization README](./README.md).

## How to see this in action

To see this policy in action, first deploy the accelerator using the instructions [here](../../README.md) setting the `USE_SIMULATOR` value to `true`.
This will deploy OpenAI API simulators to enable testing the APIM policies without the cost of Azure OpenAI API calls.

Once the accelerator is deployed, open a bash terminal in the root directory of the repo and run `LOAD_PATTERN=cycle ENDPOINT_PATH=prioritization-simple ./scripts/run-end-to-end-prioritization.sh`.

This script runs a load test that cycles between high and low priority requests sending embeddings requests:
- Initially, the script only sends low priority requests
- Then high priority requests are sent alongside the low priority requests
- Next, only high priority requests are sent
- Then low priority requests are sent alongside the high priority requests
- Finally, only low priority requests are sent

After the load test is complete, the script waits for the metrics to be ingested into Log Analytics and then queries the results.

The initial output from a test run will look something like this (the output shows the variation in test users at each step):

![output showing the test steps](./docs/output-1.png)

Once the metrics are ingested, the script will show the results of a number of queries that illustrate the behaviour:

![output showing the query results](./docs/output-2.png)

For each of these queries, the query text is included, as well as a `Run in Log Analytics` link, which will take you directly to the Log Analytics blade in the Azure Portal so that you can run the query and explore the data further.

The first query shows the overall request count and shows that the number of requests increases when we have both high and low priority requests in the load pattern:

![chart showing requests over time](./docs/query-request-count.png)

The next query shows the number of successful requests (i.e. with a 200 status response) split by priority. Here you can see that there are only successful low priority requests at the start and end of the test (when there are only low priority requests):

![chart showing the number of sucessful requests by priority](./docs/query-sucessful-requests.png)

The third query shows all responses split by priority and response status code. This has more detail than the previous query and shows that there are 429 responses for low priority requests when there is not enough capacity available:

![chart showing responses split by priority and response code](./docs/query-requests-priority-status.png)

The next query shows the remaining tokens value (min/max/mean) over time. This is the value from the backend service response headers that is used to determine the available capacity for a given deployment:

![chart showing the remaining tokens over time](./docs/query-remaining-tokens.png)

The final query uses metrics from the Azure OpenAI API simulator to show the rate limit token usage over time showing both the point in time value and the 60s sliding total. This is a useful way to evaluate the effectiveness of the policy:

![chart showing the rate-limit token usage](./docs/query-rate-limit-tokens.png)

## How the policy works

The general approach to the simple prioritization implementation is to use the `x-ratelimit-remaining-tokens` and `x-ratelimit-remaining-requests` headers that the Azure OpenAI service returns to determine the available capacity for a given deployment.

The rough flow for the prioritization policy is as follows:
1. The policy checks the priority of the request. Low priority requests are identified by either an `priority` query parameter or an `x-priority` header with a value of `low`.
2. If the request is a low priority request, the policy checks if there is sufficient available capacity to allow the request through.
3. If there is sufficient spare capacity, the request is allowed through to the backend. Otherwise it is rejected with a 429 response.
4. When a response is received from the backend, the policy retrieves the `x-ratelimit-remaining-tokens` and `x-ratelimit-remaining-requests` headers and stores this in the API Management cache. These values are used to determine available capacity the when the next request is received.

The full implementation can be found in `prioritization-simple.xml`.
There are a few aspects of the policy implementation that are worth digging into further and these are covered in the following sections.

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

### Managing low-priority only requests

Since this implementation uses the `x-ratelimit-remaining-tokens` and `x-ratelimit-remaining-requests` headers to determine the available capacity, it is essentially basing the decision to allow a low-priority request through on the remaining capacity reported after the last request was processed.
This can lead to periods where low-priority requests are not processed even though there is actually spare capacity available in the backend.

For example, consider a period of time where there are only been low-priority requests.
At some point, the remaining capacity might drop below the configured threshold and subsequent low-priority requests will receive a 429 response.
The cached capacity value is only updated when a response is received from the backend, but low-priority requests are blocked and there are no high-priority requests in this scenario.
This situation continues until the cached capacity value expires (60s for tokens), resulting in a 60s window where no requests are processed.
This cycle can repeat indefinitely if there are no high-priority requests to trigger an update to the cached capacity value, as shown in the following chart.

![chart showing low-priority requests being blocked for 1 minute periods](./docs/simple-no-additional-requests.png)

The configuration for the deployment being tested in the previous chart has 100,000 tokens per minute (TPM) available and reserves 30,000 for high-priority requests.
In this scenario (low-priority requets only), that allows for up to 70,000 TPM for low-priority requests.
Using the metrics from the API simulator, we can see that in the following chart that the 60s average TPM peaks at around 70,000 TPM and then drops to around 25,000 TPM by the time low-priority requests are resumed.
This results in a much lower rate of low-priority requests than would be expected from the configuration.

![chart showing the rate-limit token usage values](./docs/simple-no-additional-requests-token-usage.png)


To address this issue, the policy uses a `allow-additional-lowpri-request` cache value.
Whenever there is a low-priority request and the cached capacity value is below the threshold, the policy checks the `allow-additional-lowpri-request` value.
If this value is not present in the cache then an additional low-priority request is allowed through which enables the gateway to update the cached capacity value.
Whenever there is a successful request, this value is set to `false` with a 10s expiry time which ensures that we wait 10s before allowing one of the additional low-priority requests through.
The following chart shows the impact of this additional request on the processing of low-priority requests.

![chart showing smaller periods of 429 responses for low-priority requests](./docs/simple-with-additional-requests.png)

In the previous chart, there are still periods where low-priority requests are blocked, but these are much shorter than in the previous chart.
In particular, note that there is only a single 10s data point where there are no low-priority requests processed.
Allowing the additional requests has a positive impact on the responsiveness of the gateway to low-priority requests when there are no high-priority requests, but it does come at the cost of intermittently allowing higher low-priority usage than the configured threshold.
This can be seen in the following chart.

![chart showing higher than configured threshold with additional requests allowed](./docs/simple-with-additional-requests-token-usage.png)




***TODO - finish doc!***
