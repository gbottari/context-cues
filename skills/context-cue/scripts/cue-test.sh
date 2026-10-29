#!/usr/bin/env bash
# Fired-or-silent tests for context cues. Runs each cue folder's tests.json through the
# dispatcher, with that cue installed alone in a throwaway folder and its markers in
# another, so a marker left by an earlier run cannot turn a fired case silent.
#
#   bash cue-test.sh ~/.claude/context-cues/my-cue [another cue folder ...]
#
# tests.json is a list. Each entry is one case, or a matrix that expands into many:
#
#   {"want": "fired", "label": "adds a comment", "tool": "Edit",
#    "input": {"file_path": "/p/a.ts", "old_string": "x", "new_string": "// why\nx"}}
#   {"want": "silent", "label": "only reads", "command": "cat a.ts", "response": "// x"}
#   {"matrix": "command", "run": "mytool run job-1", "phrase": "mytool run"}
#
#   want      fired or silent
#   tool      tool_name, with input as tool_input; command is short for a Bash call
#   response  tool_response: a string becomes its stdout
#   session   session_id; cases that share one share the marker and the folder. Default: unique
#   setup     shell run in the case's folder before the call; the payload's cwd is that folder
#   says      text the injected prompt must contain
#
# The command matrix runs the command every way a shell runs it (fired), names it in
# arguments, messages and paths (silent), and checks once per session.
#
# A case also fails when the dispatcher writes to stderr or to its error log.
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DISPATCH=${CUE_DISPATCH:-}
if [ -z "$DISPATCH" ]; then
	for d in "$here/../../../hooks/dispatch.sh" "$HOME/.claude/hooks/context-cues/dispatch.sh"; do
		[ -r "$d" ] && DISPATCH=$d && break
	done
fi
[ -n "$DISPATCH" ] || { echo "cue-test: dispatch.sh not found; set CUE_DISPATCH" >&2; exit 2; }
[ $# -gt 0 ] || { sed -n '6p' "$0" | sed 's/^# *//' >&2; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/cue-test.XXXXXX")
trap 'rm -rf -- "$work"' EXIT

# shellcheck disable=SC2016  # jq code: its $ names are jq variables
# Turns tests.json into shell assignments: want[k], label[k], setup[k], says[k], session[k], payload[k].
CASES='
def matrix($run; $phrase): [
	["fired", "plain", $run],
	["fired", "after cd &&", "cd /tmp && " + $run],
	["fired", "after a pipe", "echo q | " + $run],
	["fired", "inside $( )", "out=$(" + $run + "); echo \"$out\""],
	["fired", "inside backticks", "out=`" + $run + "`"],
	["fired", "second line of a script", "set -e\n" + $run],
	["fired", "leading VAR=value", "TZ=Asia/Kolkata " + $run],
	["fired", "subshell", "(" + $run + " > out.json)"],
	["fired", "behind time", "time " + $run],
	["fired", "behind timeout", "timeout 30 " + $run],
	["fired", "behind env", "env FOO=1 " + $run],
	["fired", "bash -c", "bash -c '\''" + $run + "'\''"],
	["fired", "loop body", "for x in a b; do " + $run + "; done"],
	["fired", "after then", "if true; then " + $run + "; fi"],
	["fired", "if condition", "if " + $run + "; then echo ok; fi"],
	["fired", "elif condition", "if false; then :; elif " + $run + "; then echo ok; fi"],
	["fired", "while condition", "while " + $run + "; do sleep 1; done"],
	["fired", "until condition, a polling loop", "until " + $run + " | grep -q idle; do sleep 2; done"],
	["silent", "echo the phrase", "echo \"run " + $phrase + " later\""],
	["silent", "grep for the phrase", "rg -n \"" + $phrase + "\" docs"],
	["silent", "a permission pattern string", "printf '\''%s'\'' '\''Bash(" + $phrase + " *)'\''"],
	["silent", "a commit message", "git commit -m \"docs: " + $phrase + " notes\""],
	["silent", "python string", "python3 -c '\''print(\"" + $phrase + "\")'\''"],
	["silent", "heredoc body, mid-line", "cat > notes.md <<EOF\nUse " + $phrase + " for this.\nEOF"],
	["silent", "path segment", "ls ~/.claude/skills/" + $phrase],
	["silent", "unrelated command", "ls -la"],
	# What a regex cannot tell apart from a real run. Asserted so that a trigger that
	# learns to read quoting shows up here as a deliberate change.
	["fired", "LIMIT: after ; inside quotes", "echo \"read the doc; " + $phrase + " comes later\""],
	["fired", "LIMIT: heredoc line starting with it", "cat > notes.md <<EOF\n" + $run + "\nEOF"]
	] | map({want: .[0], label: .[1], command: .[2]})
	+ [{want: "silent", label: "match only in tool_response", command: "cat notes.md", response: $run},
	   {want: "fired", label: "first run in a session", command: $run, session: "matrix-twice"},
	   {want: "silent", label: "second run in the same session", command: $run, session: "matrix-twice"}];
[.[] | if .matrix == "command" then matrix(.run; .phrase)[] else . end]
| to_entries[]
| .key as $k | .value as $c
| ($c.session // "case-\($k)") as $s
| ({session_id: $s, cwd: "__CUE_TEST_DIR__",
    tool_name: ($c.tool // (if $c.command != null then "Bash" else null end)),
    tool_input: ($c.input // (if $c.command != null then {command: $c.command} else {} end))}
   + (if $c.response == null then {}
      elif ($c.response | type) == "string" then {tool_response: {stdout: $c.response}}
      else {tool_response: $c.response} end)) as $p
| "want[\($k)]=\($c.want // "" | @sh); label[\($k)]=\($c.label // "case \($k)" | @sh); setup[\($k)]=\($c.setup // "" | @sh); says[\($k)]=\($c.says // "" | @sh); session[\($k)]=\($s | @sh); payload[\($k)]=\($p | tojson | @sh)"
'

failures=0
fail() { printf 'FAIL  %s: %s\n' "$name" "$1" >&2; failures=$((failures + 1)); cue_failures=$((cue_failures + 1)); }

for dir in "$@"; do
	dir=${dir%/}
	name=${dir##*/}
	cue_failures=0
	if [ ! -r "$dir/tests.json" ]; then fail "no tests.json in $dir"; continue; fi
	[ -s "$dir/README.md" ] || fail "no README.md in $dir: say what the cue fires on, why, and any tool it needs"
	install=$work/$name/cues
	marks=$work/$name/marks
	log=$marks/context-cues/errors.log
	mkdir -p "$install" "$marks"
	cp -R "$dir" "$install/$name"
	want=() label=() setup=() says=() session=() payload=()
	script=$(jq -r "$CASES" "$dir/tests.json") || { fail "tests.json does not parse"; continue; }
	eval "$script"
	k=0 fired_cases=0
	while [ $k -lt ${#want[@]} ]; do
		case_dir=$work/$name/dirs/${session[k]}
		mkdir -p "$case_dir"
		case ${want[k]} in fired | silent) ;; *) fail "want must be fired or silent: ${label[k]}" && k=$((k + 1)) && continue ;; esac
		[ "${want[k]}" = fired ] && fired_cases=$((fired_cases + 1))
		if [ -n "${setup[k]}" ] && ! (cd "$case_dir" && bash -c "${setup[k]}") >"$work/setup.log" 2>&1; then
			fail "setup failed: ${label[k]}: $(tr '\n' ' ' <"$work/setup.log" | cut -c1-300)"
			k=$((k + 1))
			continue
		fi
		p=${payload[k]//__CUE_TEST_DIR__/$case_dir}
		out=$(cd "$case_dir" && printf '%s' "$p" | CONTEXT_CUES_DIR=$install XDG_RUNTIME_DIR=$marks bash "$DISPATCH" 2>"$work/stderr")
		got=silent
		[ -n "$out" ] && got=fired
		if [ "$got" != "${want[k]}" ]; then
			fail "want ${want[k]}, got $got: ${label[k]}"
		elif [ $got = fired ] && ! printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | length > 0' >/dev/null 2>&1; then
			fail "fired without additionalContext: ${label[k]}"
		elif [ $got = fired ] && [ -n "${says[k]}" ] &&
			! printf '%s' "$out" | jq -e --arg s "${says[k]}" '.hookSpecificOutput.additionalContext | contains($s)' >/dev/null; then
			fail "the prompt does not say \"${says[k]}\": ${label[k]}"
		fi
		[ -s "$work/stderr" ] && fail "dispatch.sh wrote to stderr: ${label[k]}: $(tr '\n' ' ' <"$work/stderr" | cut -c1-300)"
		if [ -s "$log" ]; then
			fail "error log: ${label[k]}: $(tr '\n' ' ' <"$log" | cut -c1-300)"
			: >"$log"
		fi
		k=$((k + 1))
	done
	# a cue whose trigger never matches passes every silent case
	[ $fired_cases -gt 0 ] || fail "no case wants fired, so nothing shows the cue can fire"
	[ $cue_failures -eq 0 ] && printf '%s: ok (%s cases)\n' "$name" "${#want[@]}"
done
[ $failures -eq 0 ]
