#!/usr/bin/env bash
# The dispatcher itself: the cue.ini dialect, the run-step contract, several cues on one
# call, re-arming, and a broken cue staying silent, logged once, without silencing the rest.
# shellcheck disable=SC2016  # ${VAR} in single quotes is prompt.md text, not shell
set -u
repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/dispatch-test.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
n=0 failures=0

fail() { printf 'FAIL  dispatch: %s\n' "$1" >&2; failures=$((failures + 1)); }

# cue <dir> <name> <cue.ini text> [prompt text]: writes one cue folder
cue() {
	mkdir -p "$1/$2"
	printf '%s' "$3" >"$1/$2/cue.ini"
	printf '%s\n' "${4:-$2 says hi}" >"$1/$2/prompt.md"
}

# dispatch <cues dir> <payload>: prints the injected text, or nothing. jq on Windows writes
# the line breaks of -r output as \r\n, which tr takes back out.
dispatch() {
	printf '%s' "$2" | CONTEXT_CUES_DIR=$1 XDG_RUNTIME_DIR=$work/marks bash "$repo/hooks/dispatch.sh" 2>>"$work/stderr" |
		jq -r '.hookSpecificOutput.additionalContext' | tr -d '\r'
}

probe() { jq -cn --arg s "$1" --arg q "$2" '{session_id: $s, tool_name: "Probe", tool_input: {q: $q}, cwd: "/"}'; }

# expect <label> <wanted substring or "-" for silence> <text>
expect() {
	n=$((n + 1))
	if [ "$2" = - ]; then
		[ -z "$3" ] || fail "$1: want silence, got: $3"
	else
		# %q spells out characters a log hides, such as a carriage return
		case $3 in *"$2"*) ;; *) fail "$1: want $(printf %q "$2"), got: $(printf %q "${3:-silence}")" ;; esac
	fi
}
log_lines() {
	if [ -e "$work/marks/context-cues/errors.log" ]; then grep -c -- "$1" "$work/marks/context-cues/errors.log"; else echo 0; fi
}

# --- the dialect: comments, CRLF, trailing blanks, '=' and ';' inside a value ---
D=$work/dialect
cue "$D" dialect "$(printf '; a comment\n  # an indented comment\n\n[check]  \r\nuses = tool-input\r\ntools = Probe\nfield = q\nmatch = ^a=b;c #kept$   \n')"
expect "a value keeps = ; and #" "dialect says hi" "$(dispatch "$D" "$(probe d1 'a=b;c #kept')")"
expect "trailing blanks are trimmed" - "$(dispatch "$D" "$(probe d2 'a=b;c #kept   ')")"
expect "once per session" - "$(dispatch "$D" "$(probe d1 'a=b;c #kept')")"

# --- [check] sections all pass, in order ---
C=$work/checks
cue "$C" both "$(printf '[check]\nuses = tool-input\ntools = Probe\nfield = q\nmatch = x\n\n[check]\nuses = tool-input\ntools = Probe\nfield = q\nmatch = y\n')"
expect "both checks pass" "both says hi" "$(dispatch "$C" "$(probe c1 'xy')")"
expect "only the first passes" - "$(dispatch "$C" "$(probe c2 'x')")"
expect "only the second passes" - "$(dispatch "$C" "$(probe c3 'y')")"
expect "field missing from the input" - "$(dispatch "$C" "$(jq -cn '{session_id: "c4", tool_name: "Probe", tool_input: {}}')")"

# --- two cues on one call: one message carrying both texts ---
T=$work/two
cue "$T" one "$(printf '[check]\nuses = tool-input\ntools = Probe\nmatch = go\n')"
cue "$T" two "$(printf '[check]\nuses = tool-input\ntools = Probe\nmatch = go\n')"
out=$(dispatch "$T" "$(probe t1 go)")
expect "first of two cues" "one says hi" "$out"
expect "second of two cues" "two says hi" "$out"
expect "texts joined in folder-name order" $'one says hi\n\ntwo says hi' "$out"
expect "a tool no cue names" - "$(dispatch "$T" "$(jq -cn '{session_id: "t2", tool_name: "Read", tool_input: {q: "go"}}')")"

# --- the run step: payload on stdin, CUE_* in env, exit 1 is silence, key and vars ---
R=$work/run
cue "$R" runner "$(printf '[check]\nrun = check.sh\n')" 'Hello ${WHO}, ${UNSET} stays.'
cat >"$R/runner/check.sh" <<'EOF'
q=$(jq -r .tool_input.q)
[ "$q" = skip ] && exit 1
[ "$CUE_NAME" = runner ] && [ -n "$CUE_SESSION_ID" ] && [ -f "$CUE_DIR/check.sh" ] || exit 3
printf '{"key": "%s", "vars": {"WHO": "%s"}}' "$q" "$q"
EOF
expect "vars fill the prompt" 'Hello ann, ${UNSET} stays.' "$(dispatch "$R" "$(probe r1 ann)")"
expect "same key, same session" - "$(dispatch "$R" "$(probe r1 ann)")"
expect "another key, same session" "Hello bob" "$(dispatch "$R" "$(probe r1 bob)")"
expect "exit 1 keeps it silent" - "$(dispatch "$R" "$(probe r2 skip)")"
expect "exit 1 is not an error" 0 "$(log_lines runner)"

# --- file-write with match: only text the call adds, by an editing tool or a Bash write ---
F=$work/file-write
cue "$F" comment "$(printf '[check]\nuses = file-write\npath = \\.tsx?([^[:alnum:]._-]|$)\nmatch = (^|[^:])//|/\\*\n')"
# edit <session> <tool> <tool_input JSON>, bash_call <session> <command> [stdout]: payloads
edit() { jq -cn --arg s "$1" --arg t "$2" --argjson i "$3" '{session_id: $s, tool_name: $t, tool_input: $i, cwd: "/"}'; }
bash_call() { jq -cn --arg s "$1" --arg c "$2" --arg o "${3:-}" '{session_id: $s, tool_name: "Bash", tool_input: {command: $c}, tool_response: {stdout: $o}, cwd: "/"}'; }
fw() { expect "file-write: $1" "$2" "$(dispatch "$F" "$3")"; }
said="comment says hi"
fw "Edit adds a comment" "$said" "$(edit f1 Edit '{"file_path": "/p/foo.ts", "old_string": "const a=1", "new_string": "// why\nconst a=1"}')"
fw "Write with /* */" "$said" "$(edit f2 Write '{"file_path": "/p/App.tsx", "content": "/* header */\nexport const A=1\n"}')"
fw "MultiEdit, the comment in its .ts edit" "$said" "$(edit f3 MultiEdit '{"edits": [{"file_path": "/p/x.py", "new_string": "x=1"}, {"file_path": "/p/y.ts", "new_string": "// note\nconst y=2"}]}')"
fw "a Bash heredoc" "$said" "$(bash_call f4 $'cat > src/foo.ts <<EOF\n// why\nconst a=1\nEOF')"
fw "rewording a comment" "$said" "$(edit f5 Edit '{"file_path": "/p/foo.ts", "old_string": "// old\nconst a=1", "new_string": "// new\nconst a=1"}')"
fw "Bash tee -a" "$said" "$(bash_call f6 'printf "// why\n" | tee -a src/foo.ts')"
fw "Bash sed -i" "$said" "$(bash_call f7 'sed -i "1i // why" src/foo.ts')"
fw "a Markdown file quoting a comment" - "$(edit f8 Write '{"file_path": "/p/notes.md", "content": "In src/foo.ts:\n// why\n"}')"
fw "editing beside a kept comment" - "$(edit f9 Edit '{"file_path": "/p/foo.ts", "old_string": "// keep\nconst a=1", "new_string": "// keep\nconst a=2"}')"
fw "deleting a comment" - "$(edit f10 Edit '{"file_path": "/p/foo.ts", "old_string": "// stale\nconst a=1", "new_string": "const a=1"}')"
fw "a write with no comment" - "$(edit f11 Write '{"file_path": "/p/foo.ts", "content": "export const a=1\n"}')"
fw "grep output naming a comment" - "$(bash_call f12 'grep -rn "//" src/' $'src/foo.ts:12: // x\n')"
fw "ls of a doubled slash" - "$(bash_call f13 'ls -la src//' $'foo.ts\n')"
fw "a redirect to another file" - "$(bash_call f14 'grep "//" src/foo.ts > /tmp/o.txt')"
fw "a command named like tee" - "$(bash_call f15 'mytee // src/foo.ts')"
fw "a lookalike path, foo.ts.snap" - "$(edit f16 Edit '{"file_path": "/p/foo.ts.snap", "new_string": "// x"}')"
fw "https:// is not a comment" - "$(edit f17 Write '{"file_path": "/p/u.ts", "content": "const u=\"https://x.dev\"\n"}')"
fw "a Read" - "$(jq -cn '{session_id: "f18", tool_name: "Read", tool_input: {file_path: "/p/foo.ts"}, tool_response: "// x\n"}')"
fw "first comment of a session" "$said" "$(edit f19 Write '{"file_path": "/p/a.ts", "content": "// one\n"}')"
fw "second comment, same session" - "$(edit f19 Write '{"file_path": "/p/b.ts", "content": "// two\n"}')"

# --- no carriage return reaches the agent: not from a prompt.md saved with CRLF line
# endings, and not from jq on Windows, which writes every line break of -r output as \r\n.
# These read the hook's JSON as Claude Code does, with no jq -r of their own in between. ---
# dispatch_json <cues dir> <payload>: prints the hook's JSON output
dispatch_json() {
	printf '%s' "$2" | CONTEXT_CUES_DIR=$1 XDG_RUNTIME_DIR=$work/marks bash "$repo/hooks/dispatch.sh" 2>>"$work/stderr"
}
# no_cr <label> <hook JSON>: the JSON fired and its text carries no \r
no_cr() {
	n=$((n + 1))
	case $2 in
	'') fail "$1: want fired, got silence" ;;
	*'\r'*) fail "$1: a carriage return reaches the agent: $(printf %q "$2")" ;;
	esac
}
L=$work/crlf
cue "$L/a" crlf "$(printf '[check]\nuses = tool-input\ntools = Probe\nmatch = go\n')" "$(printf 'line one\r\nline two\r')"
no_cr "a prompt.md with CRLF line endings" "$(dispatch_json "$L/a" "$(probe l1 go)")"
cue "$L/b" multiline "$(printf '[check]\nrun = check.sh\n')" "$(printf 'Hello ${WHO}.\nSecond line.')"
printf '%s\n' "printf '{\"vars\": {\"WHO\": \"ann\"}}'" >"$L/b/multiline/check.sh"
no_cr "a prompt over two lines, filled from vars" "$(dispatch_json "$L/b" "$(probe l2 go)")"
# A pattern anchored with $ must still match a line of a multi-line command.
cue "$L/c" anchored "$(printf '[check]\nuses = command\nmatch = deploy-now$\n')"
expect "a \$-anchored command on the first of two lines" "anchored says hi" \
	"$(dispatch "$L/c" "$(jq -cn '{session_id: "l3", tool_name: "Bash", tool_input: {command: "deploy-now\necho done"}}')")"

# --- a broken cue: silent, logged once per session, the others unaffected ---
B=$work/broken
ok='[check]
uses = tool-input
tools = Probe
match = .
'
cue "$B" healthy "$ok"
cue "$B" unknown-key "$(printf '[check]\nuses = tool-input\ntools = Probe\nmach = .\n')"
cue "$B" unknown-section "$(printf '[cue]\nuses = command\n')"
cue "$B" key-before-section "$(printf 'uses = command\n[check]\nuses = command\nmatch = x\n')"
cue "$B" no-equals "$(printf '[check]\nuses tool-input\n')"
cue "$B" set-twice "$(printf '[check]\nuses = tool-input\ntools = Probe\nmatch = a\nmatch = b\n')"
cue "$B" no-check "$(printf '[suppress]\nuses = tool-input\ntools = Probe\nmatch = .\n')"
cue "$B" empty ''
cue "$B" uses-and-run "$(printf '[check]\nuses = tool-input\nrun = x.sh\n')"
cue "$B" neither "$(printf '[check]\nmatch = .\n')"
cue "$B" unknown-uses "$(printf '[check]\nuses = telepathy\nmatch = .\n')"
cue "$B" no-match "$(printf '[check]\nuses = tool-input\ntools = Probe\n')"
cue "$B" bad-match "$(printf '[check]\nuses = tool-input\ntools = Probe\nmatch = (\n')"
cue "$B" bad-tools "$(printf '[check]\nuses = tool-input\ntools = [\nmatch = .\n')"
cue "$B" no-prompt "$ok"
rm "$B/no-prompt/prompt.md"
cue "$B" run-missing "$(printf '[check]\nrun = nowhere.sh\n')"
cue "$B" run-outside "$(printf '[check]\nrun = ../healthy/x.sh\n')"
cue "$B" run-crashes "$(printf '[check]\nrun = crash.sh\n')"
printf 'echo boom >&2\nexit 3\n' >"$B/run-crashes/crash.sh"
cue "$B" run-not-json "$(printf '[check]\nrun = talk.sh\n')"
printf 'echo hello\n' >"$B/run-not-json/talk.sh"
broken="unknown-key unknown-section key-before-section no-equals set-twice no-check empty uses-and-run neither unknown-uses no-match bad-match bad-tools no-prompt run-missing run-outside run-crashes run-not-json"

out=$(dispatch "$B" "$(probe b1 anything)")
expect "the healthy cue still fires" "healthy says hi" "$out"
for c in $broken; do
	expect "$c stays silent" - "$(printf '%s\n' "$out" | grep "^$c says hi")"
	expect "$c is logged" 1 "$(log_lines " $c: ")"
done
dispatch "$B" "$(probe b1 again)" >/dev/null
for c in $broken; do expect "$c is logged once per session" 1 "$(log_lines " $c: ")"; done
expect "the crash's stderr is logged" 1 "$(log_lines 'run-crashes: .*boom')"

# The tool filter joins every cue's tools into one pattern, so it must leave out a broken one.
G=$work/bad-tools-alone
cue "$G" healthy "$ok"
cue "$G" bad-tools "$(printf '[check]\nuses = tool-input\ntools = [\nmatch = .\n')"
expect "a broken tools pattern leaves the rest alone" "healthy says hi" "$(dispatch "$G" "$(probe g1 anything)")"

# --- the parse cache follows edits, removals and additions at once ---
K=$work/cache
cue "$K" edited "$(printf '[check]\nuses = tool-input\ntools = Probe\nfield = q\nmatch = ^old$\n')"
cue "$K" removed "$(printf '[check]\nuses = tool-input\ntools = Probe\nmatch = .\n')"
expect "before the edit" "edited says hi" "$(dispatch "$K" "$(probe k1 old)")"
expect "a cache is written" yes "$(for f in "$work/marks/context-cues"/parsed*cache; do [ -s "$f" ] && echo yes; done)"
printf '[check]\nuses = tool-input\ntools = Probe\nfield = q\nmatch = ^new$\n' >"$K/edited/cue.ini"
expect "an edit in the same second applies" "edited says hi" "$(dispatch "$K" "$(probe k2 new)")"
expect "the old match is gone" - "$(dispatch "$K" "$(probe k3 old)" | grep edited)"
rm -r "$K/removed"
expect "a removed cue stays silent" - "$(dispatch "$K" "$(probe k4 new)" | grep removed)"
# Built elsewhere and moved in, as the skill says, so its cue.ini is older than the cache.
cue "$work/elsewhere" added "$(printf '[check]\nuses = tool-input\ntools = Probe\nmatch = .\n')"
touch -t 202001010000 "$work/elsewhere/added/cue.ini"
mv "$work/elsewhere/added" "$K/"
expect "a cue moved in fires" "added says hi" "$(dispatch "$K" "$(probe k5 new)")"

# --- input the dispatcher refuses ---
expect "a session id with a slash" - "$(dispatch "$T" "$(probe ../x go)")"
expect "no cues folder" - "$(dispatch "$work/nowhere" "$(probe e1 go)")"
expect "a payload that is not JSON" - "$(dispatch "$T" 'not json')"

# --- re-arming: compact and clear re-arm, resume does not ---
rearm() { printf '{"session_id":"%s","source":"%s"}' "$1" "$2" | XDG_RUNTIME_DIR=$work/marks bash "$repo/hooks/rearm.sh"; }
expect "fires before re-arm" "one says hi" "$(dispatch "$T" "$(probe ra go)")"
rearm ra resume
expect "resume does not re-arm" - "$(dispatch "$T" "$(probe ra go)")"
rearm ra compact
expect "compact re-arms" "one says hi" "$(dispatch "$T" "$(probe ra go)")"
rearm ra clear
expect "clear re-arms" "one says hi" "$(dispatch "$T" "$(probe ra go)")"

# dispatch runs inside $( ), where fail() cannot count, so its stderr is checked once here
n=$((n + 1))
[ -s "$work/stderr" ] && fail "dispatch.sh wrote to stderr: $(cat "$work/stderr")"

if [ $failures -gt 0 ]; then
	printf 'dispatch-test: %s of %s checks failed\n' "$failures" "$n" >&2
	exit 1
fi
printf 'dispatch-test: ok (%s checks)\n' "$n"
