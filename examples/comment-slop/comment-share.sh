#!/usr/bin/env bash
# Run step for the comment-slop cue. Passes when the commit just made adds at least
# MIN_COMMENT comment lines and MIN_CODE code lines, and the comments are at least MIN_SHARE
# percent of the comment and code lines it adds, counted by cloc. Returns the share as SHARE
# for prompt.md. The code floor keeps a commit that only edits comments, such as a docs pass,
# silent: writing comments was its task.
set -u
MIN_COMMENT=5
MIN_CODE=5
MIN_SHARE=30
MAX_BYTES=1048576

command -v cloc >/dev/null 2>&1 || exit 1
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
cd "$top" || exit 1
git rev-parse -q --verify HEAD >/dev/null || exit 1
# A commit that failed, such as one a pre-commit hook rejected behind a `| tail` that hides
# its status, leaves an older HEAD: someone else's work, not this call's.
max_head_age_seconds=60
head_age=$(($(date +%s) - $(git log -1 --format=%ct HEAD)))
[ "$head_age" -le "$max_head_age_seconds" ] || exit 1

# A first commit has no parent, so it is compared with the empty tree.
base=$(git rev-parse -q --verify 'HEAD~1' 2>/dev/null) || base=$(git hash-object -t tree /dev/null)

old=() new=() objects=''
while IFS= read -r -d '' status && IFS= read -r -d '' f; do
	[ "$status" = A ] || { old+=(":(literal)$f"); objects+="$base:$f"$'\n'; }
	[ "$status" = D ] || { new+=(":(literal)$f"); objects+="HEAD:$f"$'\n'; }
done < <(git diff --name-status -z --no-renames "$base" HEAD)

# cloc reads every changed file in full, about 1 s per MB, and the plugin kills a hook at 10 s.
bytes=$(printf '%s' "$objects" | git cat-file --batch-check='%(objectsize)' | awk '{ t += $1 } END { print t + 0 }')
[ "$bytes" -le "$MAX_BYTES" ] || exit 1

# One archive per side keeps the cost flat; cloc's own --git mode reports nothing on Windows.
tmp=$(mktemp -d "${TMPDIR:-/tmp}/comment-slop.XXXXXX") || exit 1
trap 'rm -rf -- "$tmp"' EXIT
mkdir "$tmp/old" "$tmp/new"
[ ${#old[@]} -eq 0 ] || git archive --format=tar "$base" -- "${old[@]}" | tar -x -C "$tmp/old"
[ ${#new[@]} -eq 0 ] || git archive --format=tar HEAD -- "${new[@]}" | tar -x -C "$tmp/new"

# A rewritten line counts as modified rather than added, and is written all the same. jq on
# Windows ends its output with \r\n, which would break the arithmetic below.
read -r comment code < <(cloc --diff "$tmp/old" "$tmp/new" --json --quiet 2>/dev/null |
	jq -r '[.SUM.added, .SUM.modified] | "\(map(.comment // 0) | add) \(map(.code // 0) | add)"' 2>/dev/null | tr -d '\r')
[ -n "${comment:-}" ] && [ "$comment" -ge "$MIN_COMMENT" ] && [ "$code" -ge "$MIN_CODE" ] || exit 1
share=$((comment * 100 / (comment + code)))
[ "$share" -ge "$MIN_SHARE" ] || exit 1
jq -cn --arg share "$share" '{vars: {SHARE: $share}}'
