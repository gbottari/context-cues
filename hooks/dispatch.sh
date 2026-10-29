#!/usr/bin/env bash
# PostToolUse hook, registered once on the tools some cue checks: the dispatcher for all context cues.
#
# Each cue is a folder under $CONTEXT_CUES_DIR (default ~/.claude/context-cues) holding
# cue.ini, its checks, and prompt.md, its text. On each tool call the dispatcher runs the
# checks of every cue not yet spent in this session, and injects the prompt.md of each cue
# whose [check] sections all pass. A cue fires once per session (once per key, when a run
# step returns one); rearm.sh re-arms every cue on compact and clear.
#
# A broken cue stays silent, is written to errors.log beside the markers, and is spent for
# the session so the log gets one line per session; the other cues are unaffected.
set -u
case ${BASH_SOURCE[0]} in */*) HERE=${BASH_SOURCE[0]%/*} ;; *) HERE=. ;; esac
CUES_DIR=${CONTEXT_CUES_DIR:-$HOME/.claude/context-cues}
# Markers and the parse cache, which this script sources, must be this user's alone: in a
# shared /tmp another user could create the folder first and plant the cache. Without
# XDG_RUNTIME_DIR the folder is named for the user, and the hook runs only when it is a real
# directory the user owns.
if [ -n "${XDG_RUNTIME_DIR:-}" ]; then MARK_ROOT=$XDG_RUNTIME_DIR/context-cues; else MARK_ROOT=${TMPDIR:-/tmp}/context-cues-$UID; fi
# shellcheck disable=SC2174  # only the marker folder itself has to be private
[ -d "$MARK_ROOT" ] || mkdir -p -m 700 "$MARK_ROOT" 2>/dev/null
[ -d "$MARK_ROOT" ] && [ ! -L "$MARK_ROOT" ] && [ -O "$MARK_ROOT" ] || exit 0
ERROR_LOG="$MARK_ROOT/errors.log"
FILE_TOOLS='Edit|Write|MultiEdit|NotebookEdit'

payload=$(cat)

# Session and tool come from the raw JSON, so a call no cue cares about never starts jq.
# The patterns need unescaped quotes, so a key spelled inside a string value cannot match.
# json_field <key>: sets $field to the key's string value, or to nothing
json_field() {
	local re='"'"$1"'"[[:space:]]*:[[:space:]]*"([^"]*)"'
	field=''
	[[ $payload =~ $re ]] && field=${BASH_REMATCH[1]}
}
json_field session_id
session=$field
case $session in "" | */* | .*) exit 0 ;; esac
# sid is the marker folder. A subagent's call carries its parent's session_id and its own
# agent_id, and the subagent gets every cue once in its own context, so its markers go in
# a folder of their own inside the session's, which rearm.sh clears with the rest. The dot
# keeps that folder's name apart from every cue's. agent_id is read only before tool_input,
# because a tool's input or output can hold a key of the same name.
sid=$session
agent_re='"agent_id"[[:space:]]*:[[:space:]]*"([^"]*)"'
if [[ ${payload%%\"tool_input\"*} =~ $agent_re ]]; then
	case ${BASH_REMATCH[1]} in "" | */* | .*) exit 0 ;; esac
	sid=$session/.agent-${BASH_REMATCH[1]}
fi

# Cues not yet spent in this session. A cue's base marker spends it for every key.
cues=()
for ini in "$CUES_DIR"/*/cue.ini; do
	[ -e "$ini" ] || continue
	cue=${ini%/cue.ini}
	cue=${cue##*/}
	[ -e "$MARK_ROOT/$sid/$cue" ] || cues+=("$cue")
done
[ ${#cues[@]} -gt 0 ] || exit 0

# valid_re <ERE>: false when the pattern does not compile. Bash's =~ uses the same POSIX
# regcomp as grep, without a process, and tries it grouped, the way the checks use it.
# An empty pattern means the key is unset; BSD regcomp rejects the empty group "()".
valid_re() {
	[ -n "$1" ] || return 0
	local re="($1)"
	[[ x =~ $re ]] 2>/dev/null
	[ $? -ne 2 ]
}
spend() { { mkdir -p "$MARK_ROOT/$sid" && : >"$MARK_ROOT/$sid/$1"; } 2>/dev/null; }
fail_cue() {
	mkdir -p "$MARK_ROOT" && printf '%s %s: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$1" "$2" >>"$ERROR_LOG"
	spend "$1"
}

# Parse every cue.ini in one awk run, which prints shell code:
#   S_CUE[i]=... S_KIND[i]=... and the other S_* arrays: section i, a [check] or [suppress]
#   broken_cue ...   one call per broken cue
#   n=... wanted=... any=... fields=...
# n counts the sections; wanted and any are the tools any section could pass on, for the
# tool filter below; fields are the tool_input fields tool-input checks read. A cue can pass
# only on the tools of its first built-in [check], since every check must pass, and
# any=1 when a cue's checks are all run steps, which take any tool.
#
# The code is cached beside the markers, keyed by the cues folder, and used while every
# cue.ini and this script are older than the cache and the list of files is the same.
# Strictly older: an edit in the same second as the cache, where mtimes are whole seconds,
# parses again.
broken_cue() { [ -e "$MARK_ROOT/$sid/$1" ] || fail_cue "$1" "cue.ini: $2"; }
files=()
unreadable=''
for ini in "$CUES_DIR"/*/cue.ini; do
	[ -e "$ini" ] || continue
	if [ -r "$ini" ]; then
		files+=("$ini")
	else
		unreadable=1
		cue=${ini%/cue.ini}
		cue=${cue##*/}
		[ -e "$MARK_ROOT/$sid/$cue" ] || fail_cue "$cue" "cue.ini is not readable"
	fi
done
[ ${#files[@]} -gt 0 ] || exit 0
cache="$MARK_ROOT/parsed${CUES_DIR//\//_}"
code=''
if [ -z "$unreadable" ] && [ -f "$cache" ] && [ "${BASH_SOURCE[0]}" -ot "$cache" ]; then
	IFS= read -r first <"$cache"
	if [ "$first" = "# ${files[*]}" ]; then
		code=cached
		for ini in "${files[@]}"; do [ "$ini" -ot "$cache" ] || { code=''; break; }; done
	fi
fi
n=0 wanted='' any='' fields=''
if [ "$code" = cached ]; then
	# shellcheck source=/dev/null
	. "$cache"
else
	code=$(awk -v Q="'" -v FILE_TOOLS="$FILE_TOOLS" '
	function q(s,   out, i) {
		out = ""
		while ((i = index(s, Q)) > 0) { out = out substr(s, 1, i - 1) Q "\"" Q "\"" Q; s = substr(s, i + 1) }
		return Q out s Q
	}
	function err(msg) { if (bad == "") bad = "line " FNR ": " msg }
	function section_tools(u, t) {
		if (u == "command") return t == "" ? "Bash" : t
		if (u == "file-write") return FILE_TOOLS "|Bash"
		if (u == "tool-input") return t
		return ""
	}
	function close_section(   t) {
		if (kind == "") return
		if (cur["uses"] == "" && cur["run"] == "") err("[" kind "] needs uses or run")
		else if (cur["uses"] != "" && cur["run"] != "") err("[" kind "] has both uses and run")
		ns++
		for (k in names) sec[ns, k] = cur[k]
		sec[ns, "kind"] = kind
		# "" makes them values: gawk 5.3 crashes on an unset element passed to a function
		t = section_tools(cur["uses"] "", cur["tools"] "")
		if (kind == "suppress") { if (t != "") tools = tools "|" t }
		else {
			checks++
			if (first && t != "") { tools = tools "|" t; first = 0 }
		}
		if (cur["uses"] == "tool-input" && cur["field"] != "") flds = flds cur["field"] "\n"
		kind = ""
	}
	function flush(   i, k) {
		if (cue == "") return
		close_section()
		if (bad == "" && checks == 0) bad = "no [check] section"
		if (bad != "") { print "broken_cue " q(cue) " " q(bad); return }
		for (i = 1; i <= ns; i++) {
			printf "S_CUE[%d]=%s S_KIND[%d]=%s", n, q(cue), n, q(sec[i, "kind"])
			for (k in names) printf " %s[%d]=%s", names[k], n, q(sec[i, k])
			print ""
			n++
		}
		wanted = wanted tools
		fields = fields flds
		if (first) any = 1
	}
	BEGIN {
		split("uses run match path exclude tools field wrappers", keys)
		for (i in keys) { allowed[keys[i]] = 1; names[keys[i]] = "S_" toupper(keys[i]) }
		n = 0
	}
	FNR == 1 {
		flush()
		cue = FILENAME; sub(/\/cue\.ini$/, "", cue); sub(/.*\//, "", cue)
		bad = ""; ns = 0; checks = 0; kind = ""; first = 1; tools = ""; flds = ""; split("", cur)
	}
	{ sub(/\r$/, "") }
	/^[ \t]*([#;]|$)/ { next }
	bad != "" { next }
	/^[ \t]*\[/ {
		line = $0; sub(/^[ \t]+/, "", line); sub(/[ \t]+$/, "", line)
		close_section()
		if (line == "[check]") kind = "check"
		else if (line == "[suppress]") kind = "suppress"
		else { err("unknown section " line); next }
		split("", cur); next
	}
	{
		i = index($0, "=")
		if (i == 0) { err("no = in the line"); next }
		if (kind == "") { err("a key before the first section"); next }
		key = substr($0, 1, i - 1); val = substr($0, i + 1)
		sub(/^[ \t]+/, "", key); sub(/[ \t]+$/, "", key)
		sub(/^[ \t]+/, "", val); sub(/[ \t]+$/, "", val)
		if (!(key in allowed)) { err("unknown key " key); next }
		if (key in cur) { err(key " set twice in one section"); next }
		cur[key] = val
	}
	END {
		flush()
		print "n=" n " wanted=" q(substr(wanted, 2)) " any=" (any ? 1 : "\"\"") " fields=" q(fields)
	}
' "${files[@]}")
	eval "$code"
	if [ -z "$unreadable" ] && mkdir -p "$MARK_ROOT"; then
		printf '# %s\n%s\n' "${files[*]}" "$code" >"$cache.$$" && mv -f "$cache.$$" "$cache"
	fi
fi

# An empty cue.ini gives awk no line to read, so it produces no section at all.
live=()
for cue in "${cues[@]}"; do
	[ -e "$MARK_ROOT/$sid/$cue" ] && continue
	i=0 found=''
	while [ $i -lt $n ]; do [ "${S_CUE[i]}" = "$cue" ] && found=1 && break; i=$((i + 1)); done
	if [ -z "$found" ]; then fail_cue "$cue" "cue.ini: no [check] section"
	elif [ ! -r "$CUES_DIR/$cue/prompt.md" ]; then fail_cue "$cue" "prompt.md is missing"
	else live+=("$cue"); fi
done
[ ${#live[@]} -gt 0 ] || exit 0

tool_is() {
	local re="^($1)\$"
	[[ $tool =~ $re ]]
}
# has_line <ERE> <text>: true when a line of the text matches, as `grep -qE` would. Short
# text goes through bash's own matcher a line at a time, which saves starting grep for each
# check on each call; long text goes to grep, since bash reads a here-string byte by byte.
has_line() {
	local re=$1 line
	[ ${#2} -lt 2000 ] || { grep -qE -- "$re" <<<"$2"; return; }
	while IFS= read -r line || [ -n "$line" ]; do
		[[ $line =~ $re ]] && return 0
	done <<<"$2"
	return 1
}
# writes_path <path ERE> <exclude ERE> <names>: true when one of the file names, one per line,
# matches the path, case-insensitively, and not the exclude
writes_path() {
	local p=$1 x=$2 names=$3 line hit=1
	if [ ${#names} -ge 2000 ]; then
		if [ -n "$x" ]; then grep -vE -- "$x" <<<"$names" | grep -qiE -- "$p"; else grep -qiE -- "$p" <<<"$names"; fi
		return
	fi
	shopt -s nocasematch
	while IFS= read -r line || [ -n "$line" ]; do
		[ -n "$x" ] && [[ $line =~ $x ]] && continue
		[[ $line =~ $p ]] && hit=0 && break
	done <<<"$names"
	shopt -u nocasematch
	return $hit
}

# Skip jq when no live cue can act on this tool. A broken tools pattern must not silence
# the other cues, so it lets every call through, and check() reports it.
json_field tool_name
tool=$field
if [ -z "$any" ] && valid_re "$wanted"; then
	tool_is "$wanted" || exit 0
fi

# One jq run reads everything the checks look at, as shell assignments.
tool='' cmd='' paths='' added='' old='' input=''
targets='' targets_read=''
vars=$(jq -r --arg fields "$fields" '
	def s: if . == null then "" elif type == "string" then . else tojson end;
	def lines(f): [f | select(. != null) | s] | join("\n");
	(.tool_input // {}) as $i
	| "tool=\(.tool_name // "" | s | @sh)",
	  "cmd=\($i.command? | s | @sh)",
	  "paths=\(lines($i.file_path?, $i.notebook_path?, ($i.edits? // [] | .[]? | .file_path?)) | @sh)",
	  "added=\(lines($i.new_string?, $i.content?, $i.new_source?, ($i.edits? // [] | .[]? | .new_string?)) | @sh)",
	  "old=\(lines($i.old_string?, $i.old_source?, ($i.edits? // [] | .[]? | .old_string?)) | @sh)",
	  "input=\($i | tojson | @sh)",
	  ($fields | split("\n") | map(select(. != "")) | to_entries[] | "field_\(.key)=\($i[.value]? | s | @sh)")
' 2>/dev/null <<<"$payload") || exit 0
eval "$vars"

# shellcheck source=hooks/command-position.sh
. "$HERE/command-position.sh"

# field_value <name>: sets $value to that tool_input field, as jq read it above
field_value() {
	local f=0 name
	value=''
	for name in $fields; do
		if [ "$name" = "$1" ]; then eval "value=\$field_$f" && return; fi
		f=$((f + 1))
	done
}
# trim and dedupe lines, dropping blank ones
norm() { sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' | sort -u; }
keep() { if [ -n "$1" ]; then grep -E -- "($1)"; else cat; fi; }

# write_targets: prints the files the Bash command writes, one per line, so a path pattern
# sees each one whole, the way it sees an Edit's file_path: redirect targets, tee's file
# operands, and the operands of sed -i and perl -i. Words split on blanks with quotes
# dropped, so a quoted name holding a space comes out in pieces.
write_targets() {
	awk -v Q="'" '
	function emit(t) { gsub("[\"" Q "]", "", t); if (t != "") print t }
	{
		ns = split($0, seg, /[|;&]/)
		for (s = 1; s <= ns; s++) {
			nw = split(seg[s], w, /[ \t]+/)
			mode = ""; next_is_target = 0
			for (i = 1; i <= nw; i++) {
				t = w[i]
				if (t == "") continue
				if (next_is_target) { emit(t); next_is_target = 0; continue }
				if ((j = index(t, ">")) > 0) {
					r = substr(t, j + 1); sub(/^>/, "", r)
					if (r == "") next_is_target = 1; else emit(r)
					continue
				}
				if (mode != "") { if (t !~ /^-/) emit(t); continue }
				if (t ~ /(^|\/)tee$/) { mode = "tee"; continue }
				if (t ~ /(^|\/)(sed|perl)$/) {
					# -i as an option word: -i, -i.bak, -pi, -Ei, --in-place; not -MFile::Find
					for (k = i + 1; k <= nw; k++) if (w[k] ~ /^-[a-zA-Z]*i([^a-zA-Z]|$)/ || w[k] ~ /^--in-place/) { mode = "in-place"; break }
				}
			}
		}
	}'
}

# check <i>: runs section i against this call. Returns 0 when it passes, 1 when it does
# not, 2 when the section is broken, with the reason in $ERR.
check() {
	local i=$1 m=${S_MATCH[$1]} p=${S_PATH[$1]} x=${S_EXCLUDE[$1]} re new was
	ERR=''
	for re in "$m" "$p" "$x" "${S_TOOLS[$i]}" "${S_WRAPPERS[$i]}"; do
		valid_re "$re" || { ERR="invalid pattern: $re"; return 2; }
	done
	[ -n "${S_RUN[$i]}" ] && { run_step "$i"; return; }
	case ${S_USES[$i]} in
	command)
		[ -n "$m" ] || { ERR="uses = command needs match"; return 2; }
		tool_is "${S_TOOLS[$i]:-Bash}" || return 1
		cue_command_re "($m)" "${S_WRAPPERS[$i]}"
		has_line "$CUE_COMMAND_RE" "$cmd"
		;;
	file-write)
		[ -n "$p" ] || { ERR="uses = file-write needs path"; return 2; }
		p="($p)"
		if tool_is "$FILE_TOOLS"; then
			writes_path "$p" "$x" "$paths" || return 1
			new=$(keep "$m" <<<"$added" | norm)
			[ -n "$new" ] || return 1
			# an Edit quotes the lines around it verbatim, so the match has to be new
			[ -n "$old" ] || return 0
			was=$(keep "$m" <<<"$old" | norm)
			[ -z "$was" ] || grep -qvxF -f <(printf '%s\n' "$was") <<<"$new"
		elif tool_is Bash; then
			[ -n "$x" ] && has_line "$x" "$cmd" && return 1
			# most commands write nothing, and those skip the awk run; the rest run it once
			case $cmd in *'>'* | *tee* | *sed* | *perl*) ;; *) return 1 ;; esac
			[ -n "$targets_read" ] || { targets=$(write_targets <<<"$cmd"); targets_read=1; }
			writes_path "$p" "$x" "$targets" || return 1
			[ -z "$m" ] || has_line "($m)" "$cmd"
		else
			return 1
		fi
		;;
	tool-input)
		[ -n "${S_TOOLS[$i]}" ] && [ -n "$m" ] || { ERR="uses = tool-input needs tools and match"; return 2; }
		tool_is "${S_TOOLS[$i]}" || return 1
		if [ -n "${S_FIELD[$i]}" ]; then
			field_value "${S_FIELD[$i]}"
			has_line "($m)" "$value"
		else
			has_line "($m)" "$input"
		fi
		;;
	*)
		ERR="unknown uses = ${S_USES[$i]}"
		return 2
		;;
	esac
}

# run_step <i>: runs the section's script with the payload on stdin. Exit 0 passes and may
# print {"key": "...", "vars": {...}}; exit 1 does not pass; any other exit is an error.
# A script still running after RUN_SECONDS is killed and counts as an error, so one hung
# step cannot hold every call up to Claude Code's 10 s hook timeout, which would kill the
# hook before the step is logged and spent, and silence the cues after it.
RUN_SECONDS=5
run_step() {
	local script=$CUES_DIR/$cue/${S_RUN[$1]} out rc tmp pid dog
	case ${S_RUN[$1]} in /* | *..*) ERR="run must name a file inside the cue folder"; return 2 ;; esac
	[ -f "$script" ] || { ERR="run: ${S_RUN[$1]} not found"; return 2; }
	tmp=$(mktemp -d "${TMPDIR:-/tmp}/context-cues.XXXXXX")
	printf '%s' "$payload" >"$tmp/in"
	case $script in
	*.sh) CUE_NAME=$cue CUE_SESSION_ID=$session CUE_DIR=$CUES_DIR/$cue bash "$script" <"$tmp/in" >"$tmp/out" 2>"$tmp/err" & ;;
	*) CUE_NAME=$cue CUE_SESSION_ID=$session CUE_DIR=$CUES_DIR/$cue "$script" <"$tmp/in" >"$tmp/out" 2>"$tmp/err" & ;;
	esac
	pid=$!
	# The watchdog must not hold the hook's stdout open, or Claude Code waits for it.
	{ sleep $RUN_SECONDS && kill "$pid" && : >"$tmp/timed-out"; } >/dev/null 2>&1 &
	dog=$!
	wait "$pid"
	rc=$?
	kill "$dog" 2>/dev/null
	out=$(<"$tmp/out")
	if [ -e "$tmp/timed-out" ]; then
		ERR="run: ${S_RUN[$1]} timed out after ${RUN_SECONDS}s"
		rc=2
	elif [ $rc -gt 1 ]; then
		ERR="run: ${S_RUN[$1]} exited $rc: $(tr '\n' ' ' <"$tmp/err" | cut -c1-300)"
	fi
	rm -rf "$tmp"
	[ $rc -le 1 ] || return 2
	[ $rc -eq 0 ] || return 1
	[ -n "$out" ] || return 0
	# -s reads the whole output, so a second object fails here instead of in the prompt fill
	out=$(printf '%s' "$out" | jq -cs 'if length == 1 and (.[0] | type) == "object" then .[0] else error end
		| {key: (.key // "" | tostring), vars: (.vars // {} | with_entries(.value |= tostring))}' 2>/dev/null) ||
		{ ERR="run: ${S_RUN[$1]} printed something other than one JSON object"; return 2; }
	key=$(printf '%s' "$out" | jq -r .key)
	cue_vars=$(printf '%s' "$out" | jq -c .vars)
	return 0
}

# key_mark <key>: the marker name for one key of the current cue
key_mark() { printf '%s@%s' "$cue" "$(printf '%s' "$1" | cksum | awk '{ print $1 "-" $2 }')"; }

text=
for cue in "${live[@]}"; do
	key='' cue_vars='{}' state=pass i=0
	# a matching [suppress] spends the cue without a word
	while [ $i -lt $n ]; do
		if [ "${S_CUE[i]}" = "$cue" ] && [ "${S_KIND[i]}" = suppress ]; then
			check $i
			case $? in 0) state=suppressed && break ;; 2) state=broken && break ;; esac
		fi
		i=$((i + 1))
	done
	if [ $state = pass ]; then
		i=0
		while [ $i -lt $n ]; do
			if [ "${S_CUE[i]}" = "$cue" ] && [ "${S_KIND[i]}" = check ]; then
				check $i
				case $? in 1) state=silent && break ;; 2) state=broken && break ;; esac
			fi
			i=$((i + 1))
		done
	fi
	case $state in
	suppressed) spend "$cue" ;;
	broken) fail_cue "$cue" "$ERR" ;;
	pass)
		mark=$cue
		[ -n "$key" ] && mark=$(key_mark "$key")
		[ -e "$MARK_ROOT/$sid/$mark" ] && continue
		# a cue that cannot be marked spent would fire on every call
		spend "$mark" || continue
		if [ "$cue_vars" = '{}' ]; then
			t=$(cat "$CUES_DIR/$cue/prompt.md")
		else
			t=$(jq -rn --rawfile t "$CUES_DIR/$cue/prompt.md" --argjson v "$cue_vars" '
				reduce ($v | to_entries[] | select(.key | test("^[A-Za-z_][A-Za-z0-9_]*$"))) as $e
					($t; gsub("\\$\\{" + $e.key + "\\}"; $e.value))')
		fi
		text="$text${text:+

}$t"
		;;
	esac
done

[ -n "$text" ] || exit 0
# A prompt.md saved with CRLF line endings, and a prompt filled in by jq on Windows, both
# carry \r; the agent gets plain line breaks.
jq -n --arg t "${text//$'\r'/}" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$t}}'
