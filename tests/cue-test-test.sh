#!/usr/bin/env bash
# The skill's cue-test.sh itself: it must fail a cue it cannot show firing, since a cue whose
# trigger never matches passes every silent case.
set -u
repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/cue-test-test.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
n=0 failures=0

# expect_exit <label> <want: pass or fail> <cue folder>
expect_exit() {
	n=$((n + 1))
	local got=pass
	bash "$repo/skills/context-cue/scripts/cue-test.sh" "$3" >/dev/null 2>&1 || got=fail
	[ "$got" = "$2" ] || { printf 'FAIL  cue-test: %s: want %s, got %s\n' "$1" "$2" "$got" >&2; failures=$((failures + 1)); }
}

# cue <name> <tests.json>: a cue on Probe calls whose q is "go"
cue() {
	mkdir -p "$work/$1"
	printf '[check]\nuses = tool-input\ntools = Probe\nfield = q\nmatch = ^go$\n' >"$work/$1/cue.ini"
	printf 'Hi.\n' >"$work/$1/prompt.md"
	printf 'A test cue.\n' >"$work/$1/README.md"
	printf '%s\n' "$2" >"$work/$1/tests.json"
}
cue fires-and-stays-silent '[{"want": "fired", "tool": "Probe", "input": {"q": "go"}}, {"want": "silent", "tool": "Probe", "input": {"q": "no"}}]'
cue no-cases '[]'
cue silent-only '[{"want": "silent", "tool": "Probe", "input": {"q": "no"}}]'

expect_exit "a fired case and a silent case" pass "$work/fires-and-stays-silent"
expect_exit "no cases at all" fail "$work/no-cases"
expect_exit "only silent cases" fail "$work/silent-only"

if [ $failures -gt 0 ]; then
	printf 'cue-test-test: %s of %s checks failed\n' "$failures" "$n" >&2
	exit 1
fi
printf 'cue-test-test: ok (%s checks)\n' "$n"
