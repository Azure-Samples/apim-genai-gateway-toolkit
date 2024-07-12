#!/bin/bash
set -e

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"


# NOTES:
# USER_COUNT includes 1 for the orchestrator user
# RUN_TIME matches the duration of the orchestrator test user run

RUN_TIME=5m USER_COUNT=2 ENDPOINT_PATH=batch-processing-alt1 TEST_FILE=scenario_batch_processing.py "$script_dir/utils/run-end-to-end-test.sh"
