# Prioritization

## Capability

In this capability we have different priorities of request (high and low).
High priority requests should always be allowed through to the backend, while low priority requests should be allowed through only if there is sufficient spare capacity remaining.

An example use for this capability would be when you have purchased provisioned throughput and want to utilize any spare capacity for low-priority requests.

There are two implementations of the prioritization policy:
- [Simple](./prioritization-simple.md)
- [Token-counting](./prioritization-token-counting.md)


***TODO - comparison to token-counting implementation***
- lag in simple implementation when rate-limited from backend (especially when no high-priority requests are processed)
- complexity/maintenance cost



## Running the prioritization end-to-end test

***TODO revisit and simplify**

### Examples

Run the prioritization test with only low-priority requests using the token-counting implementation:

```bash
LOAD_PATTERN=low-priority ENDPOINT_PATH=prioritization-token-counting ./scripts/run-end-to-end-prioritization.sh
```

Run the prioritization test with only low-priority requests using the simple implementation:

```bash
LOAD_PATTERN=low-priority ENDPOINT_PATH=prioritization-simple ./scripts/run-end-to-end-prioritization.sh
```

Run the prioritization test cycling through low, high and mixed priority requests using the token-counting implementation (defaults to embeddings requests):

```bash
LOAD_PATTERN=cycle ENDPOINT_PATH=prioritization-token-counting ./scripts/run-end-to-end-prioritization.sh
```

Run the prioritization test cycling through low, high and mixed priority chat requests (with max_tokens=1000) using the simple implementation adding 10 users per second when the load stage changes:

```bash
LOAD_PATTERN=cycle REQUEST_TYPE=chat MAX_TOKENS=1000 RAMP_RATE=10 ENDPOINT_PATH=prioritization-simple ./scripts/run-end-to-end-prioritization.sh
```




