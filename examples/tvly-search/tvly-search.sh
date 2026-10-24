#!/usr/bin/env bash
# PostToolUse hook: inject how to read `tvly search` results once per session, the first
# time a Bash command runs one. It lands beside the first result set, whose scores it
# tells the agent to read.
#
# It extends a third-party skill (Tavily's search skill) without editing it, so updates
# to that skill can be pulled without merging local changes.
#
# Register on `Bash`; rearm.sh re-arms it on compact and clear.
set -u
CUE_NAME="tvly-search"
case ${BASH_SOURCE[0]} in */*) HERE=${BASH_SOURCE[0]%/*} ;; *) HERE=. ;; esac
CUE_FILE="$HERE/$CUE_NAME.cue.md"
PREFILTER='tvly'                               # cheap reject over the raw payload
ACT='tvly[[:space:]]+search([[:space:]]|$)'    # the act: a search being run, not the phrase in an argument
MARK_ROOT="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/context-cues"

[ -r "$CUE_FILE" ] || exit 0

payload=$(cat)
printf '%s' "$payload" | grep -qE "$PREFILTER" || exit 0

sid=$(printf '%s' "$payload" | jq -r '.session_id // empty')
[ -n "$sid" ] || exit 0
mark="$MARK_ROOT/$sid/$CUE_NAME"
[ -e "$mark" ] && exit 0

# shellcheck source=/dev/null  # installed beside this hook
. "$HERE/command-position.sh"
cue_command_re "$ACT"
printf '%s' "$payload" | jq -r '.tool_input.command // empty' | grep -qE "$CUE_COMMAND_RE" || exit 0

mkdir -p "${mark%/*}" && : > "$mark"
jq -n --rawfile t "$CUE_FILE" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$t}}'
