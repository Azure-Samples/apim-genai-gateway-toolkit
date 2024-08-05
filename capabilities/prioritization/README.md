# Prioritization

## Capability

## How the policy works
TODO - two implementations: outline and link to each doc



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

Run the prioritization test cycling through low, high and mixed priority requests using the token-counting implementation:

```bash
LOAD_PATTERN=cycle ENDPOINT_PATH=prioritization-token-counting ./scripts/run-end-to-end-prioritization.sh
```
