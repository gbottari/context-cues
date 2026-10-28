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

# A first commit has no parent, so it is compared with the empty tree.
base=$(git rev-parse -q --verify 'HEAD~1' 2>/dev/null) || base=$(git hash-object -t tree /dev/null)

# The changed files go into two folders, before and after, for `cloc --diff`. cloc's own
# `--git` mode must not be used: on Windows it reads back an empty archive and reports nothing.
tmp=$(mktemp -d "${TMPDIR:-/tmp}/comment-slop.XXXXXX") || exit 1
trap 'rm -rf -- "$tmp"' EXIT
mkdir "$tmp/old" "$tmp/new"
while IFS= read -r -d '' f; do
	for side in old new; do
		[ $side = old ] && rev=$base || rev=HEAD
		git cat-file -e "$rev:$f" 2>/dev/null || continue
		mkdir -p "$tmp/$side/$(dirname "$f")"
		git show "$rev:$f" >"$tmp/$side/$f"
	done
done < <(git diff --name-only -z --no-renames "$base" HEAD)

# A rewritten line counts as modified rather than added, and is written all the same. jq on
# Windows ends its output with \r\n, which would break the arithmetic below.
read -r comment code < <(cloc --diff "$tmp/old" "$tmp/new" --json --quiet 2>/dev/null |
	jq -r '[.SUM.added, .SUM.modified] | "\(map(.comment // 0) | add) \(map(.code // 0) | add)"' 2>/dev/null | tr -d '\r')
[ -n "${comment:-}" ] && [ "$comment" -ge "$MIN_COMMENT" ] && [ "$code" -ge "$MIN_CODE" ] || exit 1
share=$((comment * 100 / (comment + code)))
[ "$share" -ge "$MIN_SHARE" ] || exit 1
jq -cn --arg share "$share" '{vars: {SHARE: $share}}'
