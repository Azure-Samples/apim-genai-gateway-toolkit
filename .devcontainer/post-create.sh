#!/bin/bash
set -e

# Install any python packages needed
pip install -r policies/latency-routing/scripts/requirements.txt

# Install application-insights extension
 az extension add --name  application-insights
 