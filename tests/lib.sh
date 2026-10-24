# shellcheck shell=bash
# Sourced by the tests. Builds a throwaway install folder laid out like
# ~/.claude/context-cues (helpers and example cues side by side), then loads the same
# test helpers the skill ships, so the tests exercise what users install.

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=skills/context-cue/cue-test.sh
. "$repo/skills/context-cue/cue-test.sh"
CUES="$CUE_TEST_MARKS/install"
mkdir -p "$CUES"
cp "$repo"/hooks/*.sh "$repo"/examples/*/* "$CUES"/
