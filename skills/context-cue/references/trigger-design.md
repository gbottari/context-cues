# Trigger design: how a cue misfires

A context cue gets **one shot per session**. Every way a trigger can be wrong reduces to spending that shot on the wrong tool call, and all of them fail silently: the marker is set, the cue looks like it fired, and the work it governs happens unguided.

The built-in checks in `cue.ini` are built to avoid the first three traps and the fifth; the patterns you give them, and any run step you write, can still walk into all five. Worked example throughout: the TypeScript-comments cue in the Context Cues repository (<https://github.com/gbottari/context-cues/tree/main/examples/typescript-comments>), which injects a comment-style rule the first time a session writes a comment into a `.ts`/`.tsx` file. Its first version shipped with three of the first four traps below and went months without visibly working.

## The five traps

### 1. A path gate over the whole payload

The payload includes `tool_response`. Any read whose _output_ mentions a matching path satisfies a gate on the whole payload: `grep -rn "//" src/`, `ls -la src//`, `cat` of a file that names one. Those run early and often, so the shot is gone before the first edit.

`file-write` reads only the paths **the call itself names**: `file_path`, `notebook_path`, `edits[].file_path`, and for Bash the target of a redirect, `tee` or `sed -i`. A run step that reads the payload itself keeps to `tool_input` the same way.

### 2. A content gate over the whole `tool_input`

Flattening `tool_input` puts `old_string` in with `new_string`, so _removing_ the thing the cue governs fires the cue. `file-write` reads `match` only against what the call **adds**: `new_string`, `content`, `new_source`, `edits[].new_string`. A `tool-input` check with no `field` reads the whole input, so give it the `field` that carries the act.

### 3. Added ≠ present in `new_string`

An Edit quotes surrounding lines verbatim for uniqueness, so an untouched comment three lines up is in `new_string` too. Gating on presence fires on any edit _near_ a comment. `file-write` requires a matching line in the added text that was not in the removed text.

### 4. Over-correcting into "any touch"

Leaving `match` out so the cue lands _before_ the first comment is written trades one silent failure for another: it now fires on any write to a matching file, spending the shot where there was nothing to guide. Keep `match` when the act is narrower than writing the file. The cost is real but bounded: the first comment of a session goes unguided, and every one after it is covered. Leave it out only when the write itself is the act, as for a cue on editing agent-facing docs.

### 5. A command name matched anywhere in the command

A cue about _running_ a tool fires on every command that only spells the tool's name, if the name is matched anywhere: a commit message, an `echo`, a grep pattern, a doc written through a heredoc. In one session three cues fired this way, about 18 KB of cue text, each spending its shot before its tool ran.

`command` matches the name at **command position**: the start of a line, after `;` `&` `|`, inside `$(` or backticks, or the string given to `sh -c`, with `VAR=value` assignments and wrapper words (`time`, `env`, `timeout 30`) allowed before it. Give `match` the command and its subcommand, ending on a word boundary spelled out, and `wrappers` for what the tool is run behind:

```ini
[check]
uses = command
match = tvly[[:space:]]+search([[:space:]]|$)
wrappers = npx|pnpm[[:space:]]+exec
```

Two mentions still fire, because a regex cannot see quoting: text after `;` inside quotes, and a heredoc body line that starts with the command. The hook handler's `if` field does parse quoting, and stays out all the same: it drops a run behind `time`, `env` or `pnpm exec`, and it cannot see a redirect target.

## Path patterns

`\.tsx?\b` matches `foo.ts.snap`, because `\b` sits between `s` and `.`. `\b` is also missing from some regex builds. Anchor to the end of a path token instead:

```ini
path = \.tsx?([^[:alnum:]._-]|$)
```

The same goes for a command word: write `(^|[^[:alnum:]_-])tee[[:space:]]`, not `\btee\b`.

## Prove it with a matrix, not one payload

Firing once on a happy-path payload proves almost nothing; every trap above passes that test. List cases in `tests.json` and assert fired or silent both ways, one case per trap. A few rows of the TypeScript cue's list:

```json
[
  {
    "want": "fired",
    "label": "add a comment to foo.ts",
    "tool": "Edit",
    "input": {
      "file_path": "/p/foo.ts",
      "old_string": "const a=1",
      "new_string": "// why\nconst a=1"
    }
  },
  {
    "want": "silent",
    "label": "delete a comment",
    "tool": "Edit",
    "input": {
      "file_path": "/p/foo.ts",
      "old_string": "// stale\nconst a=1",
      "new_string": "const a=1"
    }
  },
  {
    "want": "silent",
    "label": "grep -rn // src",
    "command": "grep -rn \"//\" src/",
    "response": "src/foo.ts:12: // x\n"
  }
]
```

Each case gets its own session unless it names one, so one marker cannot mask a later case, and `cue-test.sh` keeps markers in a throwaway folder, so they do not survive between runs. Give two cases the same `session` to check the once-per-session marker.

Check that the list can fail, too: break the cue on purpose (widen `match`, drop the `[check]` that names the act) and watch the cases go red.

## The cue text is a trigger too

A trigger that fires correctly still does nothing if the text does not land. Two failure modes seen in practice:

- **Length.** The text arrives mid-task alongside everything else competing for attention; the longer it is, the more of it is skimmed. A paragraph is the target.
- **Explicit exceptions.** A cue that grants one (_"gets the lines it needs"_) is honest, and has also written the sentence an agent reaches for when it wants to do the thing anyway. A cue that anticipates its own exception has already conceded it.

If a cue fires (verify with `cue-test.sh`, then `claude --debug`) and behaviour still does not change, the text is the suspect, not the checks.

## Not the same as `.claude/rules`

A path-scoped `.claude/rules` file loads when Claude reads, writes or edits a matching file. Reads include a single-file view through Bash: `cat`, `head`, `tail`, `sed -n`, `grep` or `rg` on one file, with no pipes or redirects. That makes a rule the right home for a convention tied to a folder or file type, and the wrong one for a cue in three cases:

- **The act is narrower than the file.** A rule about writing comments loads on the first read of any `.ts` file, which is trap 4 above: the shot is spent where there was nothing to guide.
- **The act is running a command.** A command has no path to match.
- **The write goes through Bash.** Claude Code's docs list the Read, Write and Edit tools and the single-file view commands as triggers; a redirect, heredoc or `sed -i` is not among them, and auto mode steers agents toward Bash for small edits.

The dispatcher sees Bash and the file-editing tools, so a cue covers all three.
