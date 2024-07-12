#!/bin/bash
set -e

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

USER_COUNT=-1 ENDPOINT_PATH=retry-with-payg TEST_FILE=scenario_manage_spikes_with_payg.py "$script_dir/utils/run-end-to-end-test.sh"
