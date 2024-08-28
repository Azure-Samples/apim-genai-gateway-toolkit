#!/bin/bash
set -e

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

RUN_TIME=3m USER_COUNT=3 ENDPOINT_PATH=round-robin-weighted TEST_FILE=scenario_round_robin.py "$script_dir/utils/run-end-to-end-test.sh"
