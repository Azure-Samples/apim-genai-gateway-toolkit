#!/bin/bash
set -e

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"


# NOTES:
# USER_COUNT includes 1 for the orchestrator user
# RUN_TIME matches the duration of the orchestrator test user run

RUN_TIME=5m USER_COUNT=2 ENDPOINT_PATH=latency-routing TEST_FILE=scenario_latency_routing.py "$script_dir/utils/run-end-to-end-test.sh"
