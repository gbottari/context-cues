#!/usr/bin/env bash
# A cue whose act is running a command fires when the command is run, however it is run,
# and stays silent when a command only spells its name. A cue that fires on a mention
# spends its once-per-session marker before the real command arrives.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# bash_payload <session> <command> [tool_response stdout]
bash_payload() {
	jq -cn --arg s "$1" --arg c "$2" --arg o "${3:-}" \
		'{session_id:$s,tool_name:"Bash",tool_input:{command:$c},tool_response:{stdout:$o}}'
}

# expect <FIRED|silent> <hook> <label> <command>; every case gets a session of its own
expect() {
	check "$1" "$2" "$3" "$(bash_payload "case-$((n + 1))" "$4")"
}

# matrix <hook> <the command as it is really run> <a prose phrase naming it>
matrix() {
	local hook=$1 run=$2 phrase=$3

	expect FIRED "$hook" "plain" "$run"
	expect FIRED "$hook" "after cd &&" "cd /tmp && $run"
	expect FIRED "$hook" "after a pipe" "echo q | $run"
	expect FIRED "$hook" "inside \$( )" "out=\$($run); echo \"\$out\""
	expect FIRED "$hook" "inside backticks" "out=\`$run\`"
	expect FIRED "$hook" "second line of a script" $'set -e\n'"$run"
	expect FIRED "$hook" "leading VAR=value" "TZ=Asia/Kolkata $run"
	expect FIRED "$hook" "subshell" "($run > out.json)"
	expect FIRED "$hook" "behind time" "time $run"
	expect FIRED "$hook" "behind timeout" "timeout 30 $run"
	expect FIRED "$hook" "behind env" "env FOO=1 $run"
	expect FIRED "$hook" "bash -c" "bash -c '$run'"
	expect FIRED "$hook" "loop body" "for x in a b; do $run; done"
	expect FIRED "$hook" "after then" "if true; then $run; fi"
	expect FIRED "$hook" "if condition" "if $run; then echo ok; fi"
	expect FIRED "$hook" "elif condition" "if false; then :; elif $run; then echo ok; fi"
	expect FIRED "$hook" "while condition" "while $run; do sleep 1; done"
	expect FIRED "$hook" "until condition, a polling loop" "until $run | grep -q idle; do sleep 2; done"

	expect silent "$hook" "echo the phrase" "echo \"run $phrase later\""
	expect silent "$hook" "grep for the phrase" "rg -n \"$phrase\" docs"
	expect silent "$hook" "a permission pattern string" "printf '%s' 'Bash($phrase *)'"
	expect silent "$hook" "a commit message" "git commit -m \"docs: $phrase notes\""
	expect silent "$hook" "python string" "python3 -c 'print(\"$phrase\")'"
	expect silent "$hook" "heredoc body, mid-line" $'cat > notes.md <<EOF\nUse '"$phrase"$' for this.\nEOF'
	expect silent "$hook" "path segment" "ls ~/.claude/skills/$phrase"
	expect silent "$hook" "unrelated command" "ls -la"

	# What a regex cannot tell apart from a real run. Asserted so that a trigger that
	# learns to read quoting shows up here as a deliberate change.
	expect FIRED "$hook" "LIMIT: after ; inside quotes" "echo \"read the doc; $phrase comes later\""
	expect FIRED "$hook" "LIMIT: heredoc line starting with it" $'cat > notes.md <<EOF\n'"$run"$'\nEOF'

	# the match lives only in tool_response
	n=$((n + 1))
	check silent "$hook" "match only in tool_response" "$(bash_payload "resp-$n" "cat notes.md" "$run")"

	# once per session: fires on the first run, silent on the second
	check FIRED "$hook" "first run in a session" "$(bash_payload "twice" "$run")"
	check silent "$hook" "second run in the same session" "$(bash_payload "twice" "$run")"
}

matrix tvly-search.sh 'tvly search "x" --json' 'tvly search'
expect silent tvly-search.sh "another tvly subcommand" 'tvly extract https://example.com'
expect silent tvly-search.sh "a longer command name" 'mytvly search x'

# re-arm: after compact the same session fires again; after resume it stays silent
printf '%s' '{"session_id":"twice","source":"resume"}' | XDG_RUNTIME_DIR="$MARKS" bash "$CUES/rearm.sh"
check silent tvly-search.sh "resume does not re-arm" "$(bash_payload "twice" 'tvly search x')"
printf '%s' '{"session_id":"twice","source":"compact"}' | XDG_RUNTIME_DIR="$MARKS" bash "$CUES/rearm.sh"
check FIRED tvly-search.sh "compact re-arms" "$(bash_payload "twice" 'tvly search x')"
printf '%s' '{"session_id":"twice","source":"clear"}' | XDG_RUNTIME_DIR="$MARKS" bash "$CUES/rearm.sh"
check FIRED tvly-search.sh "clear re-arms" "$(bash_payload "twice" 'tvly search x')"

finish command-cue-test
