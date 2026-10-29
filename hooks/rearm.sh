#!/usr/bin/env bash
# SessionStart hook: re-arm every context cue after compaction or /clear, which is
# exactly when previously injected context is lost. No-op on startup, resume and fork.
set -u
# the marker folder dispatch.sh uses, and only when it is this user's own
if [ -n "${XDG_RUNTIME_DIR:-}" ]; then MARK_ROOT=$XDG_RUNTIME_DIR/context-cues; else MARK_ROOT=${TMPDIR:-/tmp}/context-cues-$UID; fi
[ -d "$MARK_ROOT" ] && [ ! -L "$MARK_ROOT" ] && [ -O "$MARK_ROOT" ] || exit 0
payload=$(cat)
src=$(printf '%s' "$payload" | jq -r '.source // empty')
case "$src" in compact|clear) ;; *) exit 0 ;; esac
sid=$(printf '%s' "$payload" | jq -r '.session_id // empty')
[ -n "$sid" ] && rm -rf -- "${MARK_ROOT:?}/${sid:?}"
exit 0
