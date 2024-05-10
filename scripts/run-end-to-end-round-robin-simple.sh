#!/bin/bash
set -e

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

RUN_TIME=3mm USER_COUNT=2 SCENARIO_NAME=round-robin-simple "$script_dir/utils/run-end-to-end-test.sh"
