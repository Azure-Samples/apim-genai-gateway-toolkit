# Latency based routing

## Scenario

In this scenario, an external script will define the preferred instance to route the request based on the latency. APIM will then route the request to the preferred instance.

## How the policy works

- Using the `set-preferred-backends` API, the preferred backends are stored in the cache. The preferred backends are an array of URLs of the host in the preferred order.
- The `latency-routing` policy will use the `preferred-backends` array from cache to route the request to the preferred instance.
- In cases, where the `preferred-instance` responds back with 429s, the request will then be routed to the second preferred instance.