# Prioritization

## Capability

In this capability we have different priorities of request (high and low).
High priority requests should always be allowed through to the backend, while low priority requests should be allowed through only if there is sufficient spare capacity remaining.

An example use for this capability would be when you have purchased provisioned throughput and want to utilize any spare capacity for low-priority requests.

There are two implementations of the prioritization policy:

- [Token tracking](./prioritization-token-tracking.md)
- [Token calculating](./prioritization-token-calculating.md)

## Token-tracking vs token-calculating approaches

The two approaches are largely similar, but differ in the way in which they determine the available token capacity for rate limiting purposes. The token calculating approach calculates the numer of tokens using a policy expression with logic meant to approximate Azure Open AI Service's internal algorithm, while the token tracking approach relies on the returned headers from the AOAI service to set remaining capacity. The main concerns when selecting an approach to adopt are as follows:

- Token-tracking approach introduces a lag when rate-limited by the backend (especially when no high-priority requests are processed). The token calculating approach returns immediate 429s to callers given tokens are calculated internally, rather than waiting on returned AOAI headers.
- Token calculating approach adds maintenance costs to ensure consumed token calculation remains up to date with AOAI internal logic.

## Running the prioritization end-to-end test

The prioritization end to end test accepts a number of parameters that configure test behavior:

- `ENDPOINT_PATH` - Controls whether to use the token tracking or token calculating approach. Options are `prioritization-token-tracking` and `prioritization-token-calculating`.
- `LOAD_PATTERN` - Controls which test to run. Options are `low-priority` (only low priority requests), `high-priority` (only high priority requests), and `cycle` (both low and high priority requests in custom load pattern).
- `REQUEST_TYPE` - Controls whether chat or embeddings requests are sent to the endpoint. Options are `chat` and `embeddings`.
- `RAMP_RATE` - Controls the ramp rate for the locust users.
- `MAX_TOKENS` - Controls the `max_tokens` property set in chat requests.

The command to run the end to end test is as follows (only `ENDPOINT_PATH` is required):

```bash
LOAD_PATTERN=<load_pattern> ENDPOINT_PATH=<endpoint_path> REQUEST_TYPE=<request_type> RAMP_RATE=<ramp_rate> MAX_TOKENS=<max_tokens> ./scripts/run-end-to-end-prioritization.sh
```

### Examples

Run the prioritization test with only low-priority requests using the token-calculating implementation:

```bash
LOAD_PATTERN=low-priority ENDPOINT_PATH=prioritization-token-calculating ./scripts/run-end-to-end-prioritization.sh
```

Run the prioritization test with only low-priority requests using the token-tracking implementation:

```bash
LOAD_PATTERN=low-priority ENDPOINT_PATH=prioritization-token-tracking ./scripts/run-end-to-end-prioritization.sh
```

Run the prioritization test cycling through low, high and mixed priority requests using the token-tracking implementation (defaults to embeddings requests):

```bash
LOAD_PATTERN=cycle ENDPOINT_PATH=prioritization-token-tracking ./scripts/run-end-to-end-prioritization.sh
```

Run the prioritization test cycling through low, high and mixed priority chat requests (with max_tokens=1000) using the token-tracking implementation adding 10 users per second when the load stage changes:

```bash
LOAD_PATTERN=cycle REQUEST_TYPE=chat MAX_TOKENS=1000 RAMP_RATE=10 ENDPOINT_PATH=prioritization-token-tracking ./scripts/run-end-to-end-prioritization.sh
```
