#!/usr/bin/env bash
# Runs every test and exits non-zero if any failed.
set -u
dir=$(dirname "$0")
status=0
for t in "$dir"/*-test.sh; do
	bash "$t" || status=1
done
exit "$status"
