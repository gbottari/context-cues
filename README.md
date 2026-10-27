# Context Cues

Guidance for Claude Code that arrives the moment the work it governs begins.

A **context cue** is a folder with two small files: `cue.ini` says when it fires, and `prompt.md` holds the text. The first time a session does a given kind of work, such as writing a comment in a TypeScript file or running a particular CLI, a hook adds the text to the agent's context. It stays silent for the rest of the session, and re-arms after `/compact` or `/clear`, when that text has been lost.

## Why

There are three usual places to put guidance for a coding agent, and each one fails in a predictable way:

- **`AGENTS.md` and `CLAUDE.md` fade.** They load at session start. By the time the work they govern comes up, a long session has buried them.
- **A hook on every edit is noise.** The same reminder after every tool call gets ignored.
- **Path-scoped `.claude/rules` files key on a path, not on the work.** A rule loads the first time Claude reads, writes or edits a matching file, so a plain read can bring it in long before the work it governs starts. Running a command has no path, so no rule can fire on it, and a write through a Bash redirect or heredoc is not among the triggers Claude Code's docs list.

A cue fires once, right after the first tool call that does the work, while the work is still in front of the agent.

Cues also extend skills you do not own. To add your own guidance to a third-party skill, write a cue for the command the skill teaches. The skill's files stay untouched, so its updates pull cleanly. `examples/tvly-search` does this for Tavily's search skill.

## Compared with the built-in options

| Job | Context cues | `AGENTS.md` or `CLAUDE.md` | Path rules | Skills | Hooks |
| --- | :-: | :-: | :-: | :-: | :-: |
| Remind the agent the first time it runs a given command | ✅ | ❌ | ❌ | ❌ | ❌ |
| Remind the agent the first time it writes a given kind of code, Bash writes included | ✅ | ❌ | ❌ | ❌ | ❌ |
| Spend no tokens in a session where the work never comes up | ✅ | ❌ | ✅ | ❌ | ✅ |
| Keep a rule in view through most of the work | ❌ | ✅ | ❌ | ❌ | ❌ |
| Load a convention when the agent reads or edits a file in a folder or of a type | ❌ | ❌ | ✅ | ❌ | ❌ |
| Load a procedure when the agent judges the task needs it | ❌ | ❌ | ❌ | ✅ | ❌ |
| Block a tool call that meets a condition, before it runs | ❌ | ❌ | ❌ | ❌ | ✅ |

Sources: Claude Code's docs on [memory and rules](https://code.claude.com/docs/en/memory.md), [what survives compaction](https://code.claude.com/docs/en/context-window.md), [Bash reads that count as a read](https://code.claude.com/docs/en/tools-reference.md), [skills](https://code.claude.com/docs/en/skills.md) and [hooks](https://code.claude.com/docs/en/hooks.md), as of Claude Code 2.1.310. The cue column is what this repository's tests assert.

## How it works

One `PostToolUse` hook, `dispatch.sh`, runs after each call of a tool cues check (Bash, PowerShell, the file-editing tools, Agent and Skill) with the call's JSON payload on stdin: `session_id`, `tool_name`, `tool_input` and `tool_response`. For each cue folder under `~/.claude/context-cues/` it goes through four steps:

1. **Already fired?** It skips a cue whose marker file exists at `$XDG_RUNTIME_DIR/context-cues/<session_id>/<cue-name>`.
2. **Right tool?** It reads every `cue.ini` and exits when no cue can act on this tool, so a `Read` or `Grep` call costs no `jq` run.
3. **Checks.** One `jq` run pulls out what the call itself names and adds: `file_path`, `new_string`, `content`, `command`. Each `[check]` section in `cue.ini` must pass, in order. A command check matches the command only where a shell would run it, so a commit message that mentions the command stays silent.
4. **Fire.** It writes the marker and prints `{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": "<prompt.md>"}}`. Claude Code shows the text to the agent as a system reminder beside the tool result. When several cues fire on one call, their texts arrive in one reminder, in the order of their folder names.

`rearm.sh`, a `SessionStart` hook, deletes the session's markers when the session is compacted or cleared, so every cue can fire once more.

A cue that is broken, such as one with a pattern that does not compile, stays silent and is named in `$XDG_RUNTIME_DIR/context-cues/errors.log`. The other cues keep working.

## Install

Requirements: `bash`, `jq` 1.6 or later, and standard `awk`, `grep`, `sed` and `sort`.

Install the plugin from inside Claude Code (2.1.275 or later):

```
/plugin install context-cues --marketplace gbottari/context-cues
```

Or from your shell, in two steps:

```bash
claude plugin marketplace add gbottari/context-cues
claude plugin install context-cues@context-cues
```

The plugin brings the `context-cue` skill and registers `dispatch.sh` and `rearm.sh`. Your cues live in `~/.claude/context-cues/`, one folder each, and a new folder is live on the next tool call, with no settings to edit. The skill builds and tests them; to add an example cue by hand:

```bash
git clone https://github.com/gbottari/context-cues.git
mkdir -p ~/.claude/context-cues
cp -R context-cues/examples/tvly-search ~/.claude/context-cues/
```

### Without the plugin

Copy the hooks and the skill, then register the two hooks in `~/.claude/settings.json`. The hooks get their own folder, so `~/.claude/context-cues/` holds only your cues:

```bash
git clone https://github.com/gbottari/context-cues.git
cd context-cues
mkdir -p ~/.claude/hooks/context-cues ~/.claude/context-cues ~/.claude/skills
cp hooks/*.sh ~/.claude/hooks/context-cues/
cp -R skills/context-cue ~/.claude/skills/
```

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash|PowerShell|Edit|Write|MultiEdit|NotebookEdit|Agent|Task|Skill",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/context-cues/dispatch.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "compact|clear",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/context-cues/rearm.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

## Writing a cue

Ask Claude Code for one, for example: "make a context cue that reminds you how we name migrations, the first time you write one." The `context-cue` skill walks the agent through it: write `prompt.md`, choose the checks in `cue.ini`, list fired and silent cases in `tests.json`, run them with the skill's `cue-test.sh`, and move the folder into `~/.claude/context-cues/`.

A cue that fires the first time a session adds a comment to a TypeScript file:

```ini
[check]
uses = file-write
path = \.tsx?([^[:alnum:]._-]|$)
match = (^|[^:])//|/\*
```

`cue.ini` holds one `[check]` section per condition, and all of them must pass. Each uses a built-in check, or `run`, a script of your own in the cue folder:

| Check | Passes when |
| --- | --- |
| `uses = command` | a Bash call runs the command `match` names, where a shell would run it |
| `uses = file-write` | the call writes a file matching `path`, by any tool or a Bash redirect, and adds a line matching `match` |
| `uses = tool-input` | the call is one of `tools`, and the input `field` matches `match` |
| `run = <script>` | the script, given the call on stdin, exits 0. It can return a key, so the cue fires once per key, and values for `${NAME}` in `prompt.md` |

A `[suppress]` section takes the same checks. When it matches, the cue is spent for the session and says nothing. Values run raw to the end of the line, so patterns need no escaping, and comments are whole lines starting with `#` or `;`. [`SKILL.md`](skills/context-cue/SKILL.md) has every key.

The hard part is the trigger. A cue gets one shot per session, and every wrong trigger spends that shot on the wrong call without any error. [`skills/context-cue/references/trigger-design.md`](skills/context-cue/references/trigger-design.md) covers the five ways this happens.

## Examples

One example per kind of check, each a cue the author runs.

| Example | Fires on | Shows |
| --- | --- | --- |
| [`tvly-search`](examples/tvly-search) | the first `tvly search` a session runs | `command`, and extending a third-party skill |
| [`typescript-comments`](examples/typescript-comments) | the first comment a session adds to a `.ts`/`.tsx` file, through Edit, Write or Bash | `file-write` with `match`: only added text, and only text that is new |
| [`worktree-base`](examples/worktree-base) | the first subagent a session starts in its own git worktree | `tool-input`: one field of the call's input |
| [`no-remote`](examples/no-remote) | the first commit in a git repository with no remote, once per repository | `run`, a key per repository, and `${REPO}` in the prompt |
| [`agent-docs`](examples/agent-docs) | the first write to a skill, `AGENTS.md` or `CLAUDE.md`, unless the writing skill it points to is already loaded | `[suppress]`, and `exclude` |

## Tests

```bash
bash tests/run.sh
```

`tests/dispatch-test.sh` checks the dispatcher itself: the `cue.ini` dialect, the run-step contract, two cues on one call, re-arming, and a broken cue staying silent without silencing the others. Then each example's `tests.json` runs through the skill's `cue-test.sh`, the same tool the skill gives to agents: the cue is installed alone in a temporary folder, and each case is marked to fire or to stay silent. Each case is one of the traps in `trigger-design.md`, and the cases also cover once-per-session behaviour.

## Platforms

CI runs the full test suite on Linux, macOS and Windows for every push.

- **Linux:** used daily.
- **macOS:** the tests pass with the system bash 3.2.57 and BSD grep. Install `jq` if your macOS version lacks it (`brew install jq`).
- **Windows:** the tests pass under the GitHub runner's bash. For real use, Claude Code needs Git for Windows, because it runs hooks in Git Bash when Git Bash is installed and in PowerShell when it is not. Install `jq` separately (`winget install jqlang.jq`). Commands the agent runs through the PowerShell tool reach hooks as `tool_name: "PowerShell"`, so a command check that should see them needs `tools = Bash|PowerShell`. The command-position check assumes bash syntax.
- **WSL:** same as Linux.

## Limits

- **The cue arrives just after the first act, not before it.** Context from a `PreToolUse` hook also reaches the agent beside the tool result, so it lands no sooner. The first comment of a session goes unguided; every later one is covered.
- **Subagents do not get cues.** A subagent shares its parent's `session_id`, so the marker says the cue already fired, but the subagent never saw the text.
- **A regex cannot see quoting.** Text after `;` inside quotes, or a heredoc line that starts with the command, can still fire a command cue.
- **Cue text is capped at 10,000 characters** by Claude Code. Longer output is cut to a preview of the first 2,000 characters, so a long cue points to a doc instead.

## Cost

No tokens until a cue fires. The dispatcher is one process, started after each call of a tool cues check; Read, Grep and Glob start nothing. Measured inside Claude Code on Linux, it adds about 5 ms to such a call with no cues installed, and about 17 ms to a Bash call with the five examples. [`docs/performance.md`](docs/performance.md) has the measurements.

## How this was built

The code and docs were written with [Claude Code](https://claude.com/claude-code), then reviewed and tested by the author. The cues come from daily use on the author's own machine.

## Contributing

Issues and pull requests are welcome. [CONTRIBUTING.md](CONTRIBUTING.md) has the checks to run and the house rules.

## License

[MIT](LICENSE)
