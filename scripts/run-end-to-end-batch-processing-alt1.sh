#!/bin/bash
set -e

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"


# NOTES:
# USER_COUNT -1 to indicate a custom load shape

USER_COUNT=-1 ENDPOINT_PATH=batch-processing-alt1 TEST_FILE=scenario_batch_processing_alt1.py "$script_dir/utils/run-end-to-end-test.sh"