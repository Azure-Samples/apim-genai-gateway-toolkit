#!/bin/bash
set -e

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

RUN_TIME=3mm USER_COUNT=2 ENDPOINT_PATH=round-robin-simple TEST_FILE=scenario_round_robin.py "$script_dir/utils/run-end-to-end-test.sh"
