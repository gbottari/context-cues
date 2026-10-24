#!/usr/bin/env bash
# SessionStart hook: re-arm every context cue after compaction or /clear, which is
# exactly when previously injected context is lost. No-op on startup, resume and fork.
set -u
MARK_ROOT="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/context-cues"
payload=$(cat)
src=$(printf '%s' "$payload" | jq -r '.source // empty')
case "$src" in compact|clear) ;; *) exit 0 ;; esac
sid=$(printf '%s' "$payload" | jq -r '.session_id // empty')
[ -n "$sid" ] && rm -rf -- "${MARK_ROOT:?}/${sid:?}"
exit 0
