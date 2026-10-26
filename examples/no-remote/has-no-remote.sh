#!/usr/bin/env bash
# Run step for the no-remote cue. Passes when the commit ran in a git repository with no
# remote, and returns that repository as the key, so the cue fires once per repository,
# and as REPO for prompt.md.
set -u
payload=$(cat)
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')
cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty')

# Where the commit ran: `git -C <dir>` wins, then a `cd <dir>` in the command, then the session cwd.
dir=$(printf '%s' "$cmd" | grep -oE 'git[[:space:]]+-C[[:space:]]+[^[:space:];&|]+' | head -n 1 | sed -E 's/^git[[:space:]]+-C[[:space:]]+//')
[ -n "$dir" ] || dir=$(printf '%s' "$cmd" | grep -oE '(^|[;&|[:space:]])cd[[:space:]]+[^[:space:];&|]+' | head -n 1 | sed -E 's/^.*cd[[:space:]]+//')
dir=${dir#[\"\']}
dir=${dir%[\"\']}
case $dir in
"~"*) dir=$HOME${dir#\~} ;;
esac
case $dir in
"") dir=$cwd ;;
/*) ;;
*) dir=$cwd/$dir ;;
esac
[ -d "$dir" ] || exit 1

top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || exit 1
[ -z "$(git -C "$top" remote 2>/dev/null)" ] || exit 1

case $top in
"$HOME"/*) shown="~${top#"$HOME"}" ;;
*) shown=$top ;;
esac
jq -cn --arg key "$top" --arg repo "$shown" '{key: $key, vars: {REPO: $repo}}'
