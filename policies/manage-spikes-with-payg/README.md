# Managing spike across PTU instances using PAYG deployments.

## Scenario

In this scenario, the requests are routed to PAYG instances when the PTU instances are full and returning 429s.

## How the policy works

- This scenario will leverage the APIM's [`retry`](https://learn.microsoft.com/en-us/azure/api-management/retry-policy)

- The segment in the retry policy will execute **atleast once** and when the response is null (request entering first time into the retry segment) then it will be routed to the PTU instance.

- If the PTU instance responds back with 429, then the request will be routed to the PAYG instance.