# shellcheck shell=bash
# Fired-or-silent test helpers for context cues. Source it from a test script:
#
#   . ~/.claude/skills/context-cue/scripts/cue-test.sh
#   C=~/.claude/context-cues
#   check FIRED  "$C/my-cue.sh" "adds a comment" '{"session_id":"a1","tool_name":"Edit",...}'
#   check silent "$C/my-cue.sh" "deletes one"    '{"session_id":"b1","tool_name":"Edit",...}'
#   command_matrix "$C/my-command-cue.sh" 'mytool run x' 'mytool run'
#   rearm_check "$C/rearm.sh" "$C/my-command-cue.sh" 'mytool run x'
#   finish my-cue-test
#
# Give every case its own session_id, so one marker cannot mask a later case. Markers go
# to a throwaway folder, so a marker left by an earlier run cannot turn FIRED into silent.

CUE_TEST_MARKS=$(mktemp -d)
trap 'rm -rf -- "$CUE_TEST_MARKS"' EXIT
cue_test_n=0
cue_test_failures=0

# run_hook <hook path> <payload>: prints whatever the hook printed
run_hook() {
	printf '%s' "$2" | XDG_RUNTIME_DIR="$CUE_TEST_MARKS" bash "$1"
}

# check <FIRED|silent> <hook path> <label> <payload>
check() {
	local want=$1 hook=$2 label=$3 payload=$4 got=silent out
	cue_test_n=$((cue_test_n + 1))
	out=$(run_hook "$hook" "$payload")
	[ -n "$out" ] && got=FIRED
	if [ "$got" != "$want" ]; then
		printf 'FAIL  %s: want %s, got %s: %s\n' "${hook##*/}" "$want" "$got" "$label" >&2
		cue_test_failures=$((cue_test_failures + 1))
	elif [ "$got" = FIRED ] && ! printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | length > 0' >/dev/null; then
		printf 'FAIL  %s: fired without additionalContext: %s\n' "${hook##*/}" "$label" >&2
		cue_test_failures=$((cue_test_failures + 1))
	fi
}

# bash_payload <session> <command> [tool_response stdout]
bash_payload() {
	jq -cn --arg s "$1" --arg c "$2" --arg o "${3:-}" \
		'{session_id:$s,tool_name:"Bash",tool_input:{command:$c},tool_response:{stdout:$o}}'
}

# expect_command <FIRED|silent> <hook path> <label> <command>: a Bash call in a fresh session
expect_command() {
	check "$1" "$2" "$3" "$(bash_payload "case-$((cue_test_n + 1))" "$4")"
}

# command_matrix <hook path> <the command as it is really run> <a prose phrase naming it>
# Every way a shell runs the command must fire; every mere mention must stay silent.
command_matrix() {
	local hook=$1 run=$2 phrase=$3

	expect_command FIRED "$hook" "plain" "$run"
	expect_command FIRED "$hook" "after cd &&" "cd /tmp && $run"
	expect_command FIRED "$hook" "after a pipe" "echo q | $run"
	expect_command FIRED "$hook" "inside \$( )" "out=\$($run); echo \"\$out\""
	expect_command FIRED "$hook" "inside backticks" "out=\`$run\`"
	expect_command FIRED "$hook" "second line of a script" $'set -e\n'"$run"
	expect_command FIRED "$hook" "leading VAR=value" "TZ=Asia/Kolkata $run"
	expect_command FIRED "$hook" "subshell" "($run > out.json)"
	expect_command FIRED "$hook" "behind time" "time $run"
	expect_command FIRED "$hook" "behind timeout" "timeout 30 $run"
	expect_command FIRED "$hook" "behind env" "env FOO=1 $run"
	expect_command FIRED "$hook" "bash -c" "bash -c '$run'"
	expect_command FIRED "$hook" "loop body" "for x in a b; do $run; done"
	expect_command FIRED "$hook" "after then" "if true; then $run; fi"
	expect_command FIRED "$hook" "if condition" "if $run; then echo ok; fi"
	expect_command FIRED "$hook" "elif condition" "if false; then :; elif $run; then echo ok; fi"
	expect_command FIRED "$hook" "while condition" "while $run; do sleep 1; done"
	expect_command FIRED "$hook" "until condition, a polling loop" "until $run | grep -q idle; do sleep 2; done"

	expect_command silent "$hook" "echo the phrase" "echo \"run $phrase later\""
	expect_command silent "$hook" "grep for the phrase" "rg -n \"$phrase\" docs"
	expect_command silent "$hook" "a permission pattern string" "printf '%s' 'Bash($phrase *)'"
	expect_command silent "$hook" "a commit message" "git commit -m \"docs: $phrase notes\""
	expect_command silent "$hook" "python string" "python3 -c 'print(\"$phrase\")'"
	expect_command silent "$hook" "heredoc body, mid-line" $'cat > notes.md <<EOF\nUse '"$phrase"$' for this.\nEOF'
	expect_command silent "$hook" "path segment" "ls ~/.claude/skills/$phrase"
	expect_command silent "$hook" "unrelated command" "ls -la"

	# What a regex cannot tell apart from a real run. Asserted so that a trigger that
	# learns to read quoting shows up here as a deliberate change.
	expect_command FIRED "$hook" "LIMIT: after ; inside quotes" "echo \"read the doc; $phrase comes later\""
	expect_command FIRED "$hook" "LIMIT: heredoc line starting with it" $'cat > notes.md <<EOF\n'"$run"$'\nEOF'

	check silent "$hook" "match only in tool_response" "$(bash_payload "resp-$cue_test_n" "cat notes.md" "$run")"
	check FIRED "$hook" "first run in a session" "$(bash_payload "twice-$cue_test_n" "$run")"
	check silent "$hook" "second run in the same session" "$(bash_payload "twice-$((cue_test_n - 1))" "$run")"
}

# rearm_check <rearm.sh path> <hook path> <command>: compact and clear re-arm, resume does not
rearm_check() {
	local rearm=$1 hook=$2 run=$3 sid="rearm-$cue_test_n"
	check FIRED "$hook" "first run before re-arm" "$(bash_payload "$sid" "$run")"
	printf '{"session_id":"%s","source":"resume"}' "$sid" | XDG_RUNTIME_DIR="$CUE_TEST_MARKS" bash "$rearm"
	check silent "$hook" "resume does not re-arm" "$(bash_payload "$sid" "$run")"
	printf '{"session_id":"%s","source":"compact"}' "$sid" | XDG_RUNTIME_DIR="$CUE_TEST_MARKS" bash "$rearm"
	check FIRED "$hook" "compact re-arms" "$(bash_payload "$sid" "$run")"
	printf '{"session_id":"%s","source":"clear"}' "$sid" | XDG_RUNTIME_DIR="$CUE_TEST_MARKS" bash "$rearm"
	check FIRED "$hook" "clear re-arms" "$(bash_payload "$sid" "$run")"
}

# finish <test name>: reports, and exits non-zero if any case failed
finish() {
	if [ "$cue_test_failures" -gt 0 ]; then
		printf '%s: %s of %s cases failed\n' "$1" "$cue_test_failures" "$cue_test_n" >&2
		exit 1
	fi
	printf '%s: ok (%s cases)\n' "$1" "$cue_test_n"
}
