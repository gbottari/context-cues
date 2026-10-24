# shellcheck shell=bash
# Sourced by cues whose act is *running a command*. Source it after the cheap
# prefilter and the marker check, so a call the cue does not concern never reads it.
#
#   cue_command_re NAME_RE [EXTRA_WRAPPERS_RE]
#
# sets CUE_COMMAND_RE to an ERE (for `grep -E` over tool_input.command) that matches
# NAME_RE only where a shell would run it: at the start of a line, after `;` `&` `|`,
# inside `$(` or backticks, or as the string handed to `sh -c`. Between that point and
# the name it allows a subshell paren, `VAR=value` assignments, wrapper words (`time`,
# `env`), and the shell keywords a command can follow (`if`, `while`, `until`, `then`, `do`).
# EXTRA_WRAPPERS_RE adds the wrappers a tool is really run behind (`npx`, `pnpm exec`).
#
# The name spelled inside an argument stays silent: a commit message, an `echo`, a
# grep pattern, a path. A cue that fires on a mention spends its once-per-session
# marker before the real command runs.
#
# Two mentions still fire, because a regex cannot see quoting: text after `;` `&` `|`
# inside quotes, and a heredoc body line that starts with the command.
cue_command_re() {
	local name=$1 extra=${2:-} q="'\""
	local start="(^|[;&|]|\\\$\\(|\`|(ba|z)?sh[[:space:]]+-[a-z]*c[[:space:]]+[$q])"
	local wrappers='time|sudo|env|command|exec|nohup|nice|if|elif|while|until|then|do|else|!|\{|timeout[[:space:]]+[^[:space:]]+|xargs([[:space:]]+-[^[:space:]]+)*'
	local assign='[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*'
	[ -n "$extra" ] && wrappers="$wrappers|$extra"
	# shellcheck disable=SC2034  # read by the hook that sources this file
	CUE_COMMAND_RE="${start}[[:space:]]*(\\([[:space:]]*)?(($wrappers|$assign)[[:space:]]+)*$name"
}
