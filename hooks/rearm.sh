#!/usr/bin/env bash
# SessionStart hook: re-arm every context cue after compaction or /clear, which is
# exactly when previously injected context is lost. No-op on startup, resume and fork.
set -u
case ${BASH_SOURCE[0]} in */*) HERE=${BASH_SOURCE[0]%/*} ;; *) HERE=. ;; esac
# shellcheck source=hooks/mark-root.sh
. "$HERE/mark-root.sh"
mark_root_is_ours || exit 0
payload=$(cat)
src=$(printf '%s' "$payload" | jq -r '.source // empty')
case "$src" in compact|clear) ;; *) exit 0 ;; esac
sid=$(printf '%s' "$payload" | jq -r '.session_id // empty')
# the session ids dispatch.sh refuses, so the folder removed is one of its own
case $sid in "" | */* | .*) exit 0 ;; esac
rm -rf -- "${MARK_ROOT:?}/${sid:?}"
exit 0
