# Prioritization - Token Counting

## Capability

In this capability we have different priorities of request (high and low).
High priority requests should always be allowed through to the backend, whie low priority requests should be allowed through only if there is sufficient spare capacity remaining.

## How the policy works

The general flow for the prioritization policy is as follows:
1. Tokens-per-minute and requests-per-10-seconds values are retrieved for the deployment passed in the request.
2. The number of tokens utilized by the request are calculated using the same methods Azure Open AI Service [uses to compute the values for rate limiting purposes internally](https://learn.microsoft.com/azure/ai-services/openai/how-to/quota?tabs=rest#understanding-rate-limits). 
3. The policy checks that there is capacity for the request using the selected deployment's token and request limits and rejects requests beyond those limits with a 429 response.
4. Assuming there is available capacity, the policy checks the priority of the request. Low priority requests are identified by either an `priority` query parameter or an `x-priority` header with a value of `low`.
5. If the request is a high priority request, it will be passed through to the backend.
6. If the request is a low priority request, the policy checks if there is sufficient spare capacity to allow the request through. If there is sufficient capacity, the request is allowed through to the backend. Otherwise it is rejected with a 429 response.

### Prioritization configuration

The first step of the prioritization processing is retrieving the token and request limits plus the level of spare capacity to reserve for a given deployment. `tpm-limit` and `rp10s-limit` value should be set for each deployment, as well as a `low-priority-tpm-threshold` and `low-priority-rp10s-threshold` values to set the number of tokens and requests, respectively, that should unavailable fpr low priority requests.

```xml
<cache-lookup-value key="list-deployments" variable-name="list-deployments" />
<choose>
    <when condition="@(context.Variables.ContainsKey("list-deployments") == false)">
        <!-- when remaining tokens/requests goes under the low priority threshold, low-priority requests are disallowed  -->
        <set-variable name="list-deployments" value="@{
            JArray deployments = new JArray();
            deployments.Add(new JObject()
            {
                { "deployment-id", "embedding" },
                { "tpm-limit", 10000},
                { "low-priority-tpm-threshold", 3000},
                { "rp10s-limit", 10 },
                { "low-priority-rp10s-threshold", 3},
            });
            deployments.Add(new JObject()
            {
                { "deployment-id", "embedding100k" },
                { "tpm-limit", 100000},
                { "low-priority-tpm-threshold", 30000},
                { "rp10s-limit", 100 },
                { "low-priority-rp10s-threshold", 30},
            });
            deployments.Add(new JObject()
            {
                { "deployment-id", "gpt-35-turbo-10k-token" },
                { "tpm-limit", 10000},
                { "low-priority-tpm-threshold", 3000},
                { "rp10s-limit", 10 },
                { "low-priority-rp10s-threshold", 3},
            });
            deployments.Add(new JObject()
            {
                { "deployment-id", "gpt-35-turbo-100k-token" },
                { "tpm-limit", 100000},
                { "low-priority-tpm-threshold", 30000},
                { "rp10s-limit", 100 },
                { "low-priority-rp10s-threshold", 30},
            });
            return deployments;   
        }" />
        <cache-store-value key="list-deployments" value="@((JArray)context.Variables["list-deployments"])" duration="60" />
    </when>
</choose>
```

### Calculating consumed tokens

The policy calculates the number of tokens that Azure Open AI Service will compute for the request. Embeddings and chat completion requests are calculated differently:

```xml
<set-variable name="consumed-tokens" value="@{
    JObject requestBody = context.Request.Body.As<JObject>(preserveContent: true);
    if(context.Operation.Id == "embeddings_create" || requestBody.Value<string>("model") == "embedding"){
        return (int)Math.Ceiling((requestBody.Value<string>("input")).Length * 0.25);
    } else {
        if(requestBody.ContainsKey("max_tokens") && requestBody.ContainsKey("best_of")) {
            return requestBody.Value<int>("max_tokens") * requestBody.Value<int>("best_of");
        } 
        else if(requestBody.ContainsKey("max_tokens"))
        {
            return requestBody.Value<int>("max_tokens");
        }
        else
        {
            return 16;
        }
    }
}" />
```

### Rate limiting and calculating remaining tokens

Deployment specific tokens-per-minute and requests-per-10-seconds limits are used to rate limit all incoming requests using the calculated consumed tokens and remaining capacity. Requests that exceed either limit receive 429s, while `remaining-tokens` and `remaining-requests` variables are set for use in subsequent statements.

```xml
<rate-limit-by-key counter-key="@(context.Variables["selected-deployment-id"] + "|tokens-limit")"
    calls="@((int)context.Variables["tpm-limit"])"
    renewal-period="60"
    increment-count="@((int)context.Variables["consumed-tokens"])"
    increment-condition="@(context.Response.StatusCode != 429)"
    retry-after-header-name="x-apim-tokens-retry-after"
    retry-after-variable-name="tokens-retry-after"
    remaining-calls-header-name="x-apim-remaining-tokens" 
    remaining-calls-variable-name="remaining-tokens"
    total-calls-header-name="x-apim-total-tokens"/>
<rate-limit-by-key counter-key="@(context.Variables["selected-deployment-id"] + "|requests-limit")"
    calls="@((int)context.Variables["rp10s-limit"])"
    renewal-period="10"
    increment-condition="@(context.Response.StatusCode != 429)"
    retry-after-header-name="x-apim-requests-retry-after"
    retry-after-variable-name="requests-retry-after"
    remaining-calls-header-name="x-apim-remaining-requests"
    remaining-calls-variable-name="remaining-requests"
    total-calls-header-name="x-apim-total-requests"/>
```

### Determining request priority

Low priority requests are denoted by the presence of a `priority` query string parameter or `x-priority` header set to `low`:

```xml
<set-variable name="low-priority" value="@{
    if (context.Request.Url.Query.GetValueOrDefault("priority", "") == "low"){
        return true;
    }
    if (context.Request.Headers.GetValueOrDefault("x-priority", "") == "low"){
        return true;
    }
    return false;
    }" />
```

### Rate limiting low priority requests

The policy checks that the `remaining-tokens` and `remaining-requests` are above the defined low priority thresholds for the selected deployment, returning 429s for requests that fall below those thresholds:

```xml
<choose>
    <when condition="@((int)context.Variables["remaining-tokens"] < (int)context.Variables["low-priority-tpm-threshold"])">
        <return-response>
            <set-status code="429" reason="Too Many Tokens" />
            <set-header name="x-gw-ratelimit-reason" exists-action="override">
                <value>tokens-below-low-priority-threshold</value>
            </set-header>
            <!-- return the current value in the logs - useful for validation/debugging -->
            <set-header name="x-gw-ratelimit-value" exists-action="override">
                <value>@(((int)context.Variables["remaining-tokens"]).ToString())</value>
            </set-header>
            <set-body>Low priority rate-limiting triggered by token usage</set-body>
        </return-response>
    </when>
    <when condition="@((int)context.Variables["remaining-requests"] < (int)context.Variables["low-priority-rp10s-threshold"])">
        <return-response>
            <set-status code="429" reason="Too Many Requests" />
            <set-header name="x-gw-ratelimit-reason" exists-action="override">
                <value>requests-below-low-priority-threshold</value>
            </set-header>
            <!-- return the current value in the logs - useful for validation/debugging -->
            <set-header name="x-gw-ratelimit-value" exists-action="override">
                <value>@(((int)context.Variables["remaining-requests"]).ToString())</value>
            </set-header>
            <set-body>Low priority rate-limiting triggered by requests usage</set-body>
        </return-response>
    </when>
</choose>
```

## How to see this in action

To see this policy in action, first deploy the accelerator using the instructions [here](../../README.md) setting the `USE_SIMULATOR` value to `true`.
This will deploy OpenAI API simulators to enable testing the APIM policies without the cost of Azure OpenAI API calls.

Once the accelerator is deployed, open a bash terminal in the root directory of the repo and run `LOAD_PATTERN=cycle2 ENDPOINT_PATH=prioritization-token-counting ./scripts/run-end-to-end-prioritization.sh`. The command will run a prioritization end to end test against the token counting endpoint.

This script runs a load test for 12 minutes, which repeatedly sends chat completion requests to the OpenAI simulator via APIM using the token counting prioritization policy.

1. When the script starts, it sends a low number of high-priority chat completion requests, which fall under the defined limits for the deployment.

2. High priority load increases until the service begins returning 429s, as the number of requests per 10 seconds exceeds defined limits.

3. High priority load decreases, but the `max_tokens` sent in chat completion requests increase five fold. The service returns 429s, as the number of tokens per minute exceeds defined limits. 

4. High priority load decreases, while low priority requests are introduced. The defined low priority thresholds are exceeded and the service begins to return 429s, as the number of requests per 10 seconds exceeds the defined low priority threshold. Overall limits have not been exceeded, so the service returns 200s for high priority requests.

5. High priority requests stop being sent, while low priority load increases. The service initially returns 200s for low priority requests, but the threshold is again exceeded (this time without any effect from high priority requests), and the service returns 429s.

6. Low priority load decreases and high priority requests are re-introduced, but the `max_tokens` sent in chat completion requests increase five fold, once again. While overall load has decreased, the defined low priority token thresholds are exceeded and the service begins to return 429s for low priority requests, specifically.

After the load test is complete, the script waits for the metrics to be ingested into Log Analytics and then queries the results.

The initial output from a test run will look something like this (truncated for length):

![output showing the test steps](docs/token-output-1.png)

Once the script has completed and the metrics have been ingested, the script will show the query results that illustrate the behaviour. There are 6 queries that serve to illustrate the gateway behavior over the course of the test:

- Overall request count
- Successful request count by request type
- Request count by priority and response code
- Remaining tokens
- Rate-limit tokens consumed (Simulator)
- Consumed tokens (Gateway)

The query output from `Request count by priority and response code` will look like this:

![output showing the query results](docs/token-output-2.png)

The query text is included, as well as a `Run in Log Analytics` link, which will take you directly to the Log Analytics blade in the Azure Portal so that you can run the query and explore the data further.

The query in this example shows the request count over time for different response codes (200/429) returned from APIM for high and low priority requests.
In this chart, you can see the behavior illustrated in the steps above:

![Screenshot of Log Analytics query showing the weighted split of results in the backend](docs/token-output-3.png)

Each of the listed queries will output to the console and are able to be opened in the Azure Portal via the `Run in Log Analytics` link.