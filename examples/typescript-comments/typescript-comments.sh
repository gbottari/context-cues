#!/usr/bin/env bash
# PostToolUse hook: inject a comment-style cue the first time a session writes a comment
# into a .ts or .tsx file. Built from skills/context-cue/template.sh.
# Register on `Edit|Write|MultiEdit|NotebookEdit|Bash`; rearm.sh re-arms it on compact and clear.
set -u
CUE_NAME="typescript-comments"
case ${BASH_SOURCE[0]} in */*) HERE=${BASH_SOURCE[0]%/*} ;; *) HERE=. ;; esac
CUE_FILE="$HERE/$CUE_NAME.cue.md"                     # plain text; keep it out of ~/.claude/rules
PATH_RE='\.tsx?([^[:alnum:]._-]|$)'                   # the file the cue governs, anchored to a path token
ACT_RE='(^|[^:])//|/\*'                               # the act itself, over ADDED text only
MARK_ROOT="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/context-cues"

[ -r "$CUE_FILE" ] || exit 0        # a renamed or missing cue file must not break the session

payload=$(cat)

# Cheap reject only: if PATH_RE is nowhere in the payload it cannot be in tool_input either.
# Never the accept gate: tool_response satisfies it for reads that write nothing.
printf '%s' "$payload" | grep -qE "$PATH_RE" || exit 0

sid=$(printf '%s' "$payload" | jq -r '.session_id // empty')
[ -n "$sid" ] || exit 0
mark="$MARK_ROOT/$sid/$CUE_NAME"
[ -e "$mark" ] && exit 0

lines() { printf '%s' "$payload" | jq -r "$1"' | .[] | select(. != null)'; }

case "$(printf '%s' "$payload" | jq -r '.tool_name // empty')" in
  Edit|Write|MultiEdit|NotebookEdit)
    lines '[.tool_input.file_path?, .tool_input.notebook_path?,
            (.tool_input.edits? // [] | .[].file_path?)]' | grep -qiE "$PATH_RE" || exit 0

    # only what this call ADDS: old_string would fire on removing the thing
    added=$(lines '[.tool_input.new_string?, .tool_input.content?, .tool_input.new_source?,
                    (.tool_input.edits? // [] | .[].new_string?)]' \
            | grep -E "$ACT_RE" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sort -u)
    [ -n "$added" ] || exit 0

    # an Edit quotes surrounding lines verbatim, so require the match to be new
    existing=$(lines '[.tool_input.old_string?, .tool_input.old_source?,
                       (.tool_input.edits? // [] | .[].old_string?)]' \
               | grep -E "$ACT_RE" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sort -u)
    if [ -n "$existing" ]; then
      printf '%s\n' "$added" | grep -qvxF -f <(printf '%s\n' "$existing") || exit 0
    fi
    ;;
  Bash)
    cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')
    # the file must be a WRITE target: a redirect, tee, or in-place sed/perl.
    # Word boundaries are spelled out because `\b` is not portable across grep builds.
    printf '%s' "$cmd" | grep -qE \
      '(>>?[[:space:]]*['"'"'"]?[^'"'"'"|[:space:]]*'"$PATH_RE"'|(^|[^[:alnum:]_-])tee([[:space:]]+-a)?[[:space:]]+['"'"'"]?[^'"'"'"|[:space:]]*'"$PATH_RE"'|(^|[^[:alnum:]_-])(sed|perl)[[:space:]][^|;]*-i[^|;]*'"$PATH_RE"')' \
      || exit 0
    printf '%s' "$cmd" | grep -qE "$ACT_RE" || exit 0
    ;;
  *) exit 0 ;;
esac

mkdir -p "${mark%/*}" && : > "$mark"
jq -n --rawfile t "$CUE_FILE" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$t}}'
