# Prioritization - Token Calculating

- [Prioritization - Token Calculating](#prioritization---token-calculating)
  - [Capability](#capability)
  - [How to see this in action](#how-to-see-this-in-action)
  - [How the policy works](#how-the-policy-works)
    - [Prioritization configuration](#prioritization-configuration)
    - [Calculating consumed tokens](#calculating-consumed-tokens)
    - [Rate limiting and calculating remaining tokens](#rate-limiting-and-calculating-remaining-tokens)
    - [Determining request priority](#determining-request-priority)
    - [Rate limiting low priority requests](#rate-limiting-low-priority-requests)

## Capability

In this capability we have different priorities of request (high and low).
High priority requests should always be allowed through to the backend, whie low priority requests should be allowed through only if there is sufficient spare capacity remaining.

For details of how this implementation compares to the other implementations, see the the [main prioritization README](./README.md).

## How to see this in action

Due to the complexity of this capability, there are a number of end-to-end tests that can be run to see the policy in action:

  - [Embeddings: single priority](./prioritization-token-calculating-embeddings-single.md) - single priority requests, sending either just high or low priority requests
  - [Embeddings: cycle test](./prioritization-token-calculating-embeddings-cycle.md) - cycles between high and low priority requests sending embeddings requests
  - [Chat: cycle test](./prioritization-token-calculating-chat-cycle.md) - cycles between high and low priority requests sending chat requests

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
