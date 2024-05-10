#!/bin/bash
set -e

# Install any python packages needed for load tests
pip install -r end_to_end_tests/requirements.txt

# Install application-insights extension
 az extension add --name  application-insights
 