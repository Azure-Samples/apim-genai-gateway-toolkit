#!/bin/bash
set -e

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

RUN_TIME=3m USER_COUNT=3 SCENARIO_NAME=round-robin-weighted-v2 "$script_dir/utils/run-end-to-end-test.sh"
