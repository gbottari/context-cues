# Context Cues

Guidance for Claude Code that arrives the moment the work it governs begins.

A **context cue** is a small hook script plus a text file. The first time a session does a
given kind of work, such as writing a comment in a TypeScript file or running a particular
CLI, the hook adds the text to the agent's context. It stays silent for the rest of the
session, and re-arms after `/compact` or `/clear`, when that text has been lost.

## Why

There are three usual places to put guidance for a coding agent, and each one fails in a
predictable way:

- **`CLAUDE.md` fades.** It loads at session start. By the time the work it governs
  comes up, a long session has buried it.
- **A hook on every edit is noise.** The same reminder after every tool call gets ignored.
- **Path-scoped `.claude/rules` files miss Bash.** They attach when the Read tool opens a
  matching file. An agent that reads with `cat` and writes through heredocs never sees
  them, and auto mode steers agents toward exactly that.

A cue fires once, right after the first tool call that does the work, while the work is
still in front of the agent.

Cues also extend skills you do not own. To add your own guidance to a third-party skill,
write a cue for the command the skill teaches. The skill's files stay untouched, so its
updates pull cleanly. `examples/tvly-search` does this for Tavily's search skill.

## How it works

Each cue is a `PostToolUse` hook. After every matching tool call, Claude Code runs the
script with a JSON payload on stdin holding `session_id`, `tool_name`, `tool_input` and
`tool_response`. The script then goes through four steps:

1. **Cheap reject.** It greps the raw payload for its pattern and exits if the pattern
   is absent. This takes microseconds and settles most calls.
2. **Already fired?** It exits if a marker file exists at
   `$XDG_RUNTIME_DIR/context-cues/<session_id>/<cue-name>`.
3. **Precise check.** `jq` reads only what the call itself names and adds: `file_path`,
   `new_string`, `content`, `command`. A cue about running a command matches the name
   only where a shell would run it, so a commit message that mentions the command stays
   silent.
4. **Fire.** It writes the marker and prints
   `{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": "<cue text>"}}`.
   Claude Code shows the text to the agent as a system reminder beside the tool result.

`rearm.sh`, a `SessionStart` hook, deletes the session's markers when the session is
compacted or cleared, so every cue can fire once more.

## Install

Requirements: `bash`, `jq` 1.6 or later, and standard `grep`, `sed` and `sort`.

```bash
git clone <this repository> context-cues
cd context-cues
mkdir -p ~/.claude/context-cues ~/.claude/skills
cp hooks/*.sh ~/.claude/context-cues/
cp -R skills/context-cue ~/.claude/skills/
cp examples/tvly-search/* ~/.claude/context-cues/    # optional: one example cue
```

Then register the hooks in `~/.claude/settings.json`. `rearm.sh` is registered once;
each cue gets its own `PostToolUse` entry:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "compact|clear",
        "hooks": [{ "type": "command", "command": "bash ~/.claude/context-cues/rearm.sh", "timeout": 5 }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "bash ~/.claude/context-cues/tvly-search.sh", "timeout": 5 }]
      }
    ]
  }
}
```

A file-write cue such as `examples/typescript-comments` uses the matcher
`Edit|Write|MultiEdit|NotebookEdit|Bash`.

## Writing a cue

Ask Claude Code for one, for example: "make a context cue that reminds you how we name
migrations, the first time you write one." The `context-cue` skill walks the agent
through it: write the text, choose the triggers, build the hook from one of its two
templates (`file-cue-template.sh`, `command-cue-template.sh`), register it, and prove it
with a test matrix built on the skill's `cue-test.sh`. All three files install with the
skill, so the agent has them without this repository.

The hard part is the trigger. A cue gets one shot per session, and every wrong trigger
spends that shot on the wrong call without any error.
[`skills/context-cue/references/trigger-design.md`](skills/context-cue/references/trigger-design.md) covers the
five ways this happens.

## Examples

| Example | Fires on | Shows |
| --- | --- | --- |
| [`typescript-comments`](examples/typescript-comments) | the first comment a session adds to a `.ts`/`.tsx` file, through Edit, Write or Bash | the file-write template: path gate, added text only, novelty check |
| [`tvly-search`](examples/tvly-search) | the first `tvly search` a session runs | a command cue, and extending a third-party skill |

## Tests

```bash
bash tests/run.sh
```

The tests copy the hooks and examples into a temporary folder laid out like
`~/.claude/context-cues`, then run each cue against a matrix of payloads, using the same
`cue-test.sh` helpers the skill gives to agents. Each payload is
marked to fire or to stay silent, and each case is one of the traps in
`trigger-design.md`. The matrix also covers once-per-session behaviour and re-arming.

## Platforms

- **Linux:** used daily.
- **macOS:** expected to work with the system bash 3.2. Install `jq` if your macOS
  version lacks it (`brew install jq`). CI runs the tests on macOS.
- **Windows:** needs Git for Windows, because Claude Code runs hooks in Git Bash when it
  is installed and in PowerShell when it is not. Install `jq` separately
  (`winget install jqlang.jq`). Commands the agent runs through the PowerShell tool
  reach hooks as `tool_name: "PowerShell"`, so a command cue that should see them needs
  the matcher `Bash|PowerShell`. The command-position check assumes bash syntax.
- **WSL:** same as Linux.

## Limits

- **The cue arrives just after the first act, not before it.** `PreToolUse` hooks cannot
  add context. The first comment of a session goes unguided; every later one is covered.
- **Subagents do not get cues.** A subagent shares its parent's `session_id`, so the
  marker says the cue already fired, but the subagent never saw the text.
- **A regex cannot see quoting.** Text after `;` inside quotes, or a heredoc line that
  starts with the command, can still fire a command cue.
- **Cue text is capped at 10,000 characters** by Claude Code. Longer output is cut to a
  2 KB preview, so a long cue points to a doc instead.

## Cost

No tokens until a cue fires. Seven cues on `Bash` added 17.5 ms per call on Linux with
Claude Code 2.1.296, because hooks on one call run in parallel.
[`docs/performance.md`](docs/performance.md) has the measurements.

## How this was built

The code and docs were written with [Claude Code](https://claude.com/claude-code), then
reviewed and tested by the author. The cues come from daily use on the author's own
machine.

## License

[MIT](LICENSE)
