#!/bin/bash
set -e

#
# This script can be used to generate a random API key to use for the simulator
#
chars=abcdefghijklmnopqrstuvwxyz0123456789
for _ in {1..32} ; do
  echo -n "${chars:RANDOM%${#chars}:1}"
done
