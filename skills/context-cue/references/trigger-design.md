# Trigger design: how a cue misfires

A context cue gets **one shot per session**. Every way a trigger can be wrong reduces to spending that shot on the wrong tool call, and all of them fail silently: the marker is set, the cue looks like it fired, and the work it governs happens unguided.

Worked example throughout: the TypeScript-comments cue in the Context Cues repository (<https://github.com/gbottari/context-cues/tree/main/examples/typescript-comments>), which injects a comment-style rule the first time a session writes a comment into a `.ts`/`.tsx` file. Its first version shipped with three of the first four traps below and went months without visibly working.

## The five traps

### 1. A path gate over the whole payload

```bash
printf '%s' "$payload" | grep -qE '\.tsx?\b' || exit 0     # WRONG
```

The payload includes `tool_response`. Any read whose _output_ mentions a matching path satisfies it: `grep -rn "//" src/`, `ls -la src//`, `cat` of a file that names one. Those run early and often, so the shot is gone before the first edit.

Gate on paths **the call itself names**: `tool_input.file_path`, `edits[].file_path`, `tool_input.command`. Never `tool_response`.

### 2. A content gate over the whole `tool_input`

```bash
printf '%s' "$payload" | jq -r '.tool_input | tostring' | grep -qE "$ACT_RE"   # WRONG
```

`tostring` flattens `old_string` in with `new_string`, so _removing_ the thing the cue governs fires the cue. Read only what the call **adds**: `new_string`, `content`, `new_source`, `edits[].new_string`.

### 3. Added ≠ present in `new_string`

An Edit quotes surrounding lines verbatim for uniqueness, so an untouched comment three lines up is in `new_string` too. Gating on presence fires on any edit _near_ a comment.

Compare against `old_string` and require novelty:

```bash
printf '%s\n' "$added" | grep -qvxF -f <(printf '%s\n' "$existing") || exit 0
```

### 4. Over-correcting into "any touch"

Dropping the content gate so the cue lands _before_ the first comment is written trades one silent failure for another: it now fires in every session that so much as reads a matching file, spending the shot where there was nothing to guide. Keep the content gate. The cost is real but bounded: the first comment of a session goes unguided, and every one after it is covered.

### 5. A command name gated anywhere in the command

```bash
ACT='(^|[^[:alnum:]/._-])agent-browser([[:space:]]|$)'   # WRONG
```

A cue about _running_ a tool then fires on every command that only spells the tool's name: a commit message, an `echo`, a grep pattern, a doc written through a heredoc. In one session three cues fired this way, about 18 KB of cue text, each spending its shot before its tool ran.

Gate the name at **command position**: the start of a line, after `;` `&` `|`, inside `$(` or backticks, or the string given to `sh -c`, with `VAR=value` assignments and wrapper words (`time`, `env`, `timeout 30`) allowed before it. `command-position.sh` builds that regex, and `assets/command-cue-template.sh` is a complete hook that uses it:

```bash
. "$HERE/command-position.sh"
cue_command_re 'tvly[[:space:]]+search([[:space:]]|$)'   # 2nd argument: wrappers this tool is run behind
printf '%s' "$payload" | jq -r '.tool_input.command // empty' | grep -qE "$CUE_COMMAND_RE" || exit 0
```

Source it after the prefilter and the marker check, so an unrelated call never reads it.

Two mentions still fire, because a regex cannot see quoting: text after `;` inside quotes, and a heredoc body line that starts with the command. The hook handler's `if` field does parse quoting, and stays out all the same: it drops a run behind `time`, `env` or `pnpm exec`, and it cannot see a redirect target. Leaving it out costs about 4 ms per call.

`command_matrix` in `scripts/cue-test.sh` drives one fired-or-silent matrix over a command cue: one line per cue.

## Path regexes

`\.tsx?\b` matches `foo.ts.snap`, because `\b` sits between `s` and `.`. `\b` is also missing from some `grep` builds. Anchor to the end of a path token instead:

```bash
TS_PATH='\.tsx?([^[:alnum:]._-]|$)'
```

The same goes for a command word: write `(^|[^[:alnum:]_-])tee[[:space:]]`, not `\btee\b`.

## Prove it with a matrix, not one payload

Firing once on a happy-path payload proves almost nothing; every trap above passes that test. Drive a table of payloads and assert fired or silent both ways, one case per trap. With `check` from `scripts/cue-test.sh`, a few rows of that table for the TypeScript cue:

```bash
check FIRED  "$H" "add a comment to foo.ts"        '{"session_id":"a1","tool_name":"Edit","tool_input":{"file_path":"/p/foo.ts","old_string":"const a=1","new_string":"// why\nconst a=1"}}'
check silent "$H" "DELETE a comment"               '{"session_id":"b2","tool_name":"Edit","tool_input":{"file_path":"/p/foo.ts","old_string":"// stale\nconst a=1","new_string":"const a=1"}}'
check silent "$H" "grep -rn // src"                '{"session_id":"b4","tool_name":"Bash","tool_input":{"command":"grep -rn \"//\" src/"},"tool_response":{"stdout":"src/foo.ts:12: // x\n"}}'
```

Each `session_id` is distinct so one marker cannot mask a later case, and `scripts/cue-test.sh` redirects `XDG_RUNTIME_DIR` so markers do not survive between runs. Without that, the second run of the matrix reports every FIRED case as silent. Re-run one `session_id` twice to check the once-per-session marker, and pipe a `{"source":"compact"}` payload through `rearm.sh` (`rearm_check` does both) to check re-arming.

Check that the matrix can fail, too: break the hook on purpose (match the name anywhere, drop the novelty check) and watch the cases go red.

## The cue text is a trigger too

A trigger that fires correctly still does nothing if the text does not land. Two failure modes seen in practice:

- **Length.** The text arrives mid-task alongside everything else competing for attention; the longer it is, the more of it is skimmed. A paragraph is the target.
- **Explicit exceptions.** A cue that grants one (_"gets the lines it needs"_) is honest, and has also written the sentence an agent reaches for when it wants to do the thing anyway. A cue that anticipates its own exception has already conceded it.

If a cue fires (verify with the matrix, then `claude --debug`) and behaviour still does not change, the text is the suspect, not the hook.

## Not the same as `.claude/rules`

A path-scoped `.claude/rules` file loads when Claude reads, writes or edits a matching file. Reads include a single-file view through Bash: `cat`, `head`, `tail`, `sed -n`, `grep` or `rg` on one file, with no pipes or redirects. That makes a rule the right home for a convention tied to a folder or file type, and the wrong one for a cue in three cases:

- **The act is narrower than the file.** A rule about writing comments loads on the first read of any `.ts` file, which is trap 4 above: the shot is spent where there was nothing to guide.
- **The act is running a command.** A command has no path to match.
- **The write goes through Bash.** Claude Code's docs list the Read, Write and Edit tools and the single-file view commands as triggers; a redirect, heredoc or `sed -i` is not among them, and auto mode steers agents toward Bash for small edits.

A hook matching `Bash` as well as `Edit|Write` sees all three.
