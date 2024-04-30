#!/bin/bash
set -e

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

RUN_TIME=3m USER_COUNT=2 SCENARIO_NAME=round-robin-weighted "$script_dir/_run-end-to-end-test.sh"
