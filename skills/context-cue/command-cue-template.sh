#!/usr/bin/env bash
# PostToolUse hook: inject CUE_FILE once per session, the first time a Bash command runs
# the command the cue governs. Register on `Bash` (or `Bash|PowerShell` on Windows).
# Pair with rearm.sh on SessionStart so compaction and /clear re-arm it.
# See trigger-design.md, trap 5, for why the name is matched at command position.
#
# Install beside command-position.sh, in ~/.claude/context-cues/.
set -u
CUE_NAME="my-command-cue"                         # one marker per cue
case ${BASH_SOURCE[0]} in */*) HERE=${BASH_SOURCE[0]%/*} ;; *) HERE=. ;; esac
CUE_FILE="$HERE/$CUE_NAME.cue.md"
PREFILTER='mytool'                                # cheap reject over the raw payload
ACT='mytool[[:space:]]+run([[:space:]]|$)'        # the act: the command being run, not its name in an argument
WRAPPERS=''                                       # extra wrappers it is run behind, e.g. 'npx|pnpm[[:space:]]+exec'
MARK_ROOT="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/context-cues"

[ -r "$CUE_FILE" ] || exit 0        # a renamed or missing cue file must not break the session

payload=$(cat)
printf '%s' "$payload" | grep -qE "$PREFILTER" || exit 0

sid=$(printf '%s' "$payload" | jq -r '.session_id // empty')
[ -n "$sid" ] || exit 0
mark="$MARK_ROOT/$sid/$CUE_NAME"
[ -e "$mark" ] && exit 0

# shellcheck source=/dev/null  # installed beside this hook
. "$HERE/command-position.sh"
cue_command_re "$ACT" "$WRAPPERS"
printf '%s' "$payload" | jq -r '.tool_input.command // empty' | grep -qE "$CUE_COMMAND_RE" || exit 0

mkdir -p "${mark%/*}" && : > "$mark"
jq -n --rawfile t "$CUE_FILE" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$t}}'
