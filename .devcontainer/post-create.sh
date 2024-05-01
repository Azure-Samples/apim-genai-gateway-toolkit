#!/bin/bash
set -e

# Install any python packages needed for load tests
pip install -r scripts/end_to_end/requirements.txt

# Install application-insights extension
 az extension add --name  application-insights
 