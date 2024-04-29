# Load balancing across PAYG, PTU instances

## Scenario

In this scenario, 2 different flavours of load balancing are done. Simple round robin and weighted round robin.

## How the policy works

### Simple Round Robin

- All the pool of endpoints are defined as an array.
- An incrementing counter is used to select the endpoint (index) from the array.
- The counter is persisted in the cache to maintain the state across the requests.
- The selected endpoint is then used to route the request.

### Weighted Round Robin

- All the pool of endpoints are defined as an `JArray` along with the weights for each endpoint.
- A random number is generated from 0 to the sum of all the weights.
- The endpoint is selected based on the random number generated, which is then used to route the request.
- There is no persistence of the counter in this case.
