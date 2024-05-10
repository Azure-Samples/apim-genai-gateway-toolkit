#!/bin/bash
set -e

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

USER_COUNT=-1 SCENARIO_NAME=manage-spikes-with-payg "$script_dir/utils/run-end-to-end-test.sh"
