<h1 align="center">Context Cues</h1>

<p align="center">
  Just-in-time rules for Claude Code: each one fires once, at the command or edit it is about.
</p>

<p align="center">
  <a href="https://github.com/gbottari/context-cues/actions/workflows/test.yml"><img src="https://github.com/gbottari/context-cues/actions/workflows/test.yml/badge.svg" alt="test"/></a>
  <a href="https://github.com/gbottari/context-cues/releases/latest"><img src="https://img.shields.io/github/v/release/gbottari/context-cues" alt="Latest release"/></a>
  <img src="https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows%20%28Git%20Bash%29-blue" alt="Platforms: Linux, macOS, Windows (Git Bash)"/>
</p>

<p align="center">
  <a href="#-install">Install</a> · <a href="#-where-it-fits">Where it fits</a> · <a href="#-use-cases">Use cases</a> · <a href="#-limits">Limits</a> · <a href="#-examples">Examples</a>
</p>

Context cues are a token-efficient, deterministic way to steer agents during sessions. Use one to:

- **Keep a rule from fading in a long session.** `CLAUDE.md` loads at session start, while a cue arrives when the work it governs is in front of the agent.
- **Add your own guidance to any skill.** Write a cue for the command the skill teaches. The skill's files stay untouched, so its updates pull cleanly.

For example, the `comment-slop` cue fires after the first commit of a session whose added lines are at least 30% comments. The agent gets this beside the commit's output, as a system reminder ([`examples/comment-slop`](examples/comment-slop)):

> PostToolUse:Bash hook additional context: This reminder fired because comments are 32% of the lines your last commit added, which can be a sign of documentation slop. The rules for comments: a comment says why the code is the way it is now (a constraint, a decision, a trap) and leaves what it does to the code and what changed to the commit. …

Later commits in the same session add nothing.

## 🚀 Install

Requirements: Claude Code 2.1.275 or later, `bash`, and `jq` 1.6 or later.

In Claude Code:

```
/plugin install context-cues --marketplace gbottari/context-cues
```

The plugin installs the hooks and the `context-cue` skill, and no cues. Each cue you add is a folder under `~/.claude/context-cues/`.

To try it, ask Claude Code in any git repository: "make a context cue that reminds you to check which branch you are on, the first time you run `git status`." Once the cue is installed, ask it to run `git status` twice: the agent gets the reminder after the first run and nothing after the second.

See more: [installing from your shell, without the plugin, or an example cue by hand](docs/install.md).

## 🧩 Where it fits

There are three usual places to put guidance for a coding agent, and each one fails in a predictable way:

- **`AGENTS.md` and `CLAUDE.md` fade.** They load at session start. By the time the work they govern comes up, a long session has buried them.
- **A plain hook repeats itself.** Its `if` field can narrow it to one command, such as `Bash(git *)`, but it fires on every match, so the same reminder lands after every call.
- **Path-scoped `.claude/rules` files key only on file paths.** A plain read of a matching file can load one long before the work starts, and running a command never loads one.

| Job | Context cues | `AGENTS.md` or `CLAUDE.md` | Path rules | Skills | Plain hooks |
| --- | :-: | :-: | :-: | :-: | :-: |
| Remind the agent the first time it runs a given command | ✅ | ❌ | ❌ | ❌ | ❌ |
| Remind the agent the first time it writes a given kind of code, Bash writes included | ✅ | ❌ | ❌ | ❌ | ❌ |
| Spend no tokens in a session where the work never comes up | ✅ | ❌ | ✅ | ❌ | ✅ |
| Keep a rule in view through most of the work | ❌ | ✅ | ❌ | ❌ | ❌ |
| Load a convention when the agent reads or edits a file in a folder or of a type | ❌ | ❌ | ✅ | ❌ | ❌ |
| Load a procedure when the agent judges the task needs it | ❌ | ❌ | ❌ | ✅ | ❌ |
| Block a tool call that meets a condition, before it runs | ❌ | ❌ | ❌ | ❌ | ✅ |

## 🧭 Use cases

Each one starts from a problem. You ask Claude Code for a cue in plain words, and the `context-cue` skill builds and tests it. Both are in [`examples/`](examples), with their tests.

### The agent misreads a skill you didn't write

You installed a third-party skill for a search CLI. The agent takes a page of off-topic results as an answer, and fixing the skill means editing files its next update overwrites.

Ask: _"When you search with `tvly`, remind yourself how to read the scores."_ After the first `tvly search` of a session, beside the results, the agent reads:

> **Read the top `score` before the results.** Relevant hits usually score 0.65–0.90. A top score under about 0.1 means the search failed …

### A habit that is wrong in one kind of repository

Some of your repositories have no remote. After every commit there, the agent offers to push.

Ask: _"In repos with no remote, don't offer to push."_ After the first commit in each such repository, the agent reads:

> `notes` has no git remote. Don't offer or ask to push here, and don't mention the missing remote.

## ⚠️ Limits

- **The cue arrives just after the first act, not before it.** A hook's text reaches the agent together with the tool's result, so the first matching act runs before the agent reads the cue.
- **Claude Code caps hook output at 10,000 characters**, about 25 times the longest example cue. Past that it shows a 2,000-character preview, so guidance that long belongs in a doc the cue points to.

## 📐 Cue specification

A cue is a folder with two files: `cue.ini` says when it fires, and `prompt.md` holds the text injected into the agent's context.

The `context-cue` skill teaches the agent to:

- **Write the cue.** It picks the checks for `cue.ini`, writes `prompt.md` as one short standing rule, and says when the rule belongs in `CLAUDE.md` instead.
- **Test it.** `tests.json` lists the calls the cue must fire on and the ones it must stay silent on, and the skill's `cue-test.sh` runs them. A command cue gets a ready-made matrix: every way a shell runs the command, and the mentions that must stay silent.

A cue that fires the first time a session adds a comment to a TypeScript file:

```ini
[check]
uses = file-write
# a path ending in .ts or .tsx
path = \.tsx?([^[:alnum:]._-]|$)
# an added line with /* or //, but not the // in https://
match = (^|[^:])//|/\*
```

`cue.ini` holds one `[check]` section per condition, and all of them must pass. A check uses one of three built-ins, named by `uses =`:

| `uses =` | Passes when |
| --- | --- |
| `command` | a Bash call runs the command `match` names, where a shell would run it |
| `file-write` | the call writes a file matching `path`, by any tool or a Bash redirect, and adds a line matching `match` |
| `tool-input` | the call is one of `tools`, and the input `field` matches `match` |

For a condition no built-in covers, such as whether the repository has a remote, a check names a script in the cue folder instead: `run = <script>`. The script gets the call on stdin and passes by exiting 0. It can also return a key, so the cue fires once per key rather than once per session, and values for `${NAME}` in `prompt.md`.

A `[suppress]` section takes the same checks and works the other way round: when it matches a call, the cue counts as already fired, so it stays silent for the rest of the session. Use it when the agent already has what the cue would say: `agent-docs` goes quiet once the agent loads the writing skill the cue points to.

Values run raw to the end of the line, so patterns need no escaping. Comments are whole lines starting with `#` or `;`; a `#` after a value is part of the value. [`SKILL.md`](skills/context-cue/SKILL.md) has every key.

## 📂 Examples

| Example | Fires on | Pattern | Built with |
| --- | --- | --- | --- |
| [`tvly-search`](examples/tvly-search) | `tvly search` | Teach the agent to read a tool's output, on top of a skill you don't own | `command` |
| [`comment-slop`](examples/comment-slop) | a commit whose added lines are at least 30% comments, counted by cloc | Judge the result of an act with a tool of your own, and say in the cue what it found | `run`, `${SHARE}` |
| [`worktree-base`](examples/worktree-base) | a subagent started in its own git worktree | Warn about one option the agent picked for a tool call | `tool-input` |
| [`no-remote`](examples/no-remote) | a commit in a git repository with no remote, once per repository | Fire once per place instead of once per session | `run` with a key, `${REPO}` |
| [`agent-docs`](examples/agent-docs) | a write to a skill, `AGENTS.md` or `CLAUDE.md` | Stay silent when the agent already loaded the guidance | `[suppress]`, `exclude` |
| [`skill-the-user`](examples/skill-the-user) | the author's name written into a skill file | Catch a slip in what the agent writes, not every write | `file-write` with `match` |

## ⏱️ Cost

No tokens until a cue fires. One hook process starts after each call of a tool some cue checks (Bash, PowerShell, the file-editing tools, Agent and Skill); Read, Grep and Glob start nothing. Measured inside Claude Code on Linux, it adds about 5 ms to such a call with no cues installed, and about 17 ms to a Bash call with five of the examples installed. [`docs/performance.md`](docs/performance.md) has the measurements.

## ⚙️ How it works

One `PostToolUse` hook, `dispatch.sh`, runs after each call of a tool some cue checks (Bash, PowerShell, the file-editing tools, Agent and Skill) with the call's JSON payload on stdin: `session_id`, `tool_name`, `tool_input` and `tool_response`. Your cues live in `~/.claude/context-cues/`, one folder each, and a new folder is live on the next tool call. For each cue folder it goes through four steps:

1. **Already fired?** It skips a cue whose marker file exists at `$XDG_RUNTIME_DIR/context-cues/<session_id>/<cue-name>`, or under `$TMPDIR/context-cues-<uid>` when `XDG_RUNTIME_DIR` is unset. A subagent's calls keep their markers in a folder of their own inside that one, so each subagent gets every cue once in its own context.
2. **Right tool?** It reads every `cue.ini` and exits when no cue can act on this tool, so a `Read` or `Grep` call costs no `jq` run.
3. **Checks.** One `jq` run pulls out what the call itself names and adds: `file_path`, `new_string`, `content`, `command`. Each `[check]` section in `cue.ini` must pass, in order. A command check matches the command only where a shell would run it, so a commit message that mentions the command stays silent.
4. **Fire.** It writes the marker and prints `{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": "<prompt.md>"}}`. Claude Code shows the text to the agent as a system reminder beside the tool result. When several cues fire on one call, their texts arrive in one reminder, in the order of their folder names.

A cue fires again after `/compact` or `/clear`, when its text has been lost: `rearm.sh`, a `SessionStart` hook, deletes the session's markers.

A cue that is broken, such as one with a pattern that does not compile, stays silent and is named in `$XDG_RUNTIME_DIR/context-cues/errors.log`. The other cues keep working.

Context Cues makes no network calls; beside the markers it keeps only a cache of the parsed `cue.ini` files, and each run step gets a temporary folder that it removes.

_Written with [Claude Code](https://claude.com/claude-code) and reviewed by the author._
