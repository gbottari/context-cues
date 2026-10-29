#!/usr/bin/env bash
# Runs every test and exits non-zero if any failed.
set -u
repo=$(cd "$(dirname "$0")/.." && pwd)
status=0
bash "$repo/tests/dispatch-test.sh" || status=1
bash "$repo/tests/cue-test-test.sh" || status=1
bash "$repo/skills/context-cue/scripts/cue-test.sh" "$repo"/examples/*/ || status=1
exit "$status"
