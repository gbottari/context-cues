#!/usr/bin/env bash
# A cue whose act is running a command fires when the command is run, however it is run,
# and stays silent when a command only spells its name. A cue that fires on a mention
# spends its once-per-session marker before the real command arrives.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
H="$CUES/tvly-search.sh"

command_matrix "$H" 'tvly search "x" --json' 'tvly search'
expect_command silent "$H" "another tvly subcommand" 'tvly extract https://example.com'
expect_command silent "$H" "a longer command name" 'mytvly search x'
rearm_check "$CUES/rearm.sh" "$H" 'tvly search x'

# The command-cue template, filled in for a made-up tool, behaves the same way.
T="$CUES/mytool.sh"
sed -e 's/^CUE_NAME="my-command-cue"/CUE_NAME="mytool"/' \
	-e "s/^WRAPPERS=''/WRAPPERS='npx'/" "$repo/skills/context-cue/assets/command-cue-template.sh" > "$T"
printf 'Use mytool carefully.\n' > "$CUES/mytool.cue.md"
command_matrix "$T" 'mytool run job-1' 'mytool run'
expect_command FIRED "$T" "behind an extra wrapper" 'npx mytool run job-1'

finish command-cue-test
