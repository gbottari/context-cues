# shellcheck shell=bash
# Sourced by dispatch.sh and rearm.sh, which must agree on the marker folder: sets MARK_ROOT.
#
# Markers and the parse cache, which dispatch.sh sources, must be this user's alone: in a
# shared /tmp another user could create the folder first and plant the cache. Without
# XDG_RUNTIME_DIR the folder is named for the user, and a hook runs only when it is a real
# directory the user owns.
if [ -n "${XDG_RUNTIME_DIR:-}" ]; then MARK_ROOT=$XDG_RUNTIME_DIR/context-cues; else MARK_ROOT=${TMPDIR:-/tmp}/context-cues-$UID; fi
mark_root_is_ours() { [ -d "$MARK_ROOT" ] && [ ! -L "$MARK_ROOT" ] && [ -O "$MARK_ROOT" ]; }
