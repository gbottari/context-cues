# shellcheck shell=bash
# Sourced by the tests. Builds a throwaway install folder laid out like
# ~/.claude/context-cues (helpers and example cues side by side), and a marker root of
# its own, so a stale marker from an earlier run cannot turn a FIRED case into a silent one.

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
CUES="$work/context-cues"
MARKS="$work/marks"
mkdir -p "$CUES" "$MARKS"
cp "$repo"/hooks/*.sh "$repo"/examples/*/* "$CUES"/

n=0
failures=0

# run_hook <hook file> <payload>: prints whatever the hook printed
run_hook() {
	printf '%s' "$2" | XDG_RUNTIME_DIR="$MARKS" bash "$CUES/$1"
}

# check <FIRED|silent> <hook file> <label> <payload>
check() {
	local want=$1 hook=$2 label=$3 payload=$4 got=silent out
	n=$((n + 1))
	out=$(run_hook "$hook" "$payload")
	[ -n "$out" ] && got=FIRED
	if [ "$got" != "$want" ]; then
		printf 'FAIL  %s: want %s, got %s: %s\n' "$hook" "$want" "$got" "$label" >&2
		failures=$((failures + 1))
	elif [ "$got" = FIRED ] && ! printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | length > 0' >/dev/null; then
		printf 'FAIL  %s: fired without additionalContext: %s\n' "$hook" "$label" >&2
		failures=$((failures + 1))
	fi
}

# finish <test name>
finish() {
	if [ "$failures" -gt 0 ]; then
		printf '%s: %s of %s cases failed\n' "$1" "$failures" "$n" >&2
		exit 1
	fi
	printf '%s: ok (%s cases)\n' "$1" "$n"
}
