<h1 align="center">Context Cues</h1>

<p align="center">
  Just-in-time rules for Claude Code: each one fires once, at the command or edit it is about.
</p>

<p align="center">
  <a href="https://github.com/gbottari/context-cues/actions/workflows/test.yml"><img src="https://github.com/gbottari/context-cues/actions/workflows/test.yml/badge.svg" alt="test"/></a>
  <a href="https://github.com/gbottari/context-cues/releases/latest"><img src="https://img.shields.io/github/v/release/gbottari/context-cues" alt="Latest release"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/gbottari/context-cues" alt="License: MIT"/></a>
  <img src="https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-blue" alt="Platforms: Linux, macOS, Windows"/>
</p>

<p align="center">
  <a href="#-install">Install</a> · <a href="#-where-it-fits">Where it fits</a> · <a href="#-use-cases">Use cases</a> · <a href="#-limits">Limits</a> · <a href="#-examples">Examples</a>
</p>

Context cues are a token-efficient, deterministic way to steer agents during sessions. Use one to:

- **Keep a rule from fading in a long session.** `CLAUDE.md` loads at session start, while a cue arrives when the work it governs is in front of the agent.
- **Add your own guidance to any skill.** Write a cue for the command the skill teaches. The skill's files stay untouched, so its updates pull cleanly.

For example, a cue for Tavily's search CLI fires after the first `tvly search` of a session. The agent gets this beside the search results, as a system reminder ([`examples/tvly-search`](examples/tvly-search)):

```text
PostToolUse:Bash hook additional context: Reading `tvly search` results:

- Read the top `score` before the results. Relevant hits usually score 0.65–0.90. A top score under about 0.1 means the search failed: …
```

Later searches in the same session add nothing.

## 🚀 Install

Requirements: Claude Code 2.1.275 or later, `bash`, and `jq` 1.6 or later.

In Claude Code:

```
/plugin install context-cues --marketplace gbottari/context-cues
```

To make your first cue, ask Claude Code: "make a context cue that reminds you the staging database is a day old, the first time you query it."

See more: [installing from your shell, without the plugin, or an example cue by hand](docs/install.md).

## 🧩 Where it fits

There are three usual places to put guidance for a coding agent, and each one fails in a predictable way:

- **`AGENTS.md` and `CLAUDE.md` fade.** They load at session start. By the time the work they govern comes up, a long session has buried them.
- **A plain hook repeats itself.** Its `if` field can narrow it to one command, such as `Bash(git *)`, but it fires on every match, so the same reminder lands after every call.
- **Path-scoped `.claude/rules` files key only on file paths.** A plain read of a matching file can load one long before the work starts, and running a command never loads one.

For a skill you don't own, `examples/tvly-search` shows how: a cue on `tvly search` adds guidance to Tavily's search skill.

Anthropic's own plugins come closest. `security-guidance` adds a reminder once per file when an edit introduces a risky pattern, but only for its security rules and only on edits. `hookify` takes your own rules on commands and edits, but fires on every match, and an open issue ([#20747](https://github.com/anthropics/claude-code/issues/20747)) reports that its warnings reach you, not the agent. Context Cues is the general form: your own rules, on a command, a file write through any tool or a Bash redirect, or any tool input, each fired once and tested.

| Job | Context cues | `AGENTS.md` or `CLAUDE.md` | Path rules | Skills | Hooks |
| --- | :-: | :-: | :-: | :-: | :-: |
| Remind the agent the first time it runs a given command | ✅ | ❌ | ❌ | ❌ | ❌ |
| Remind the agent the first time it writes a given kind of code, Bash writes included | ✅ | ❌ | ❌ | ❌ | ❌ |
| Spend no tokens in a session where the work never comes up | ✅ | ❌ | ✅ | ❌ | ✅ |
| Keep a rule in view through most of the work | ❌ | ✅ | ❌ | ❌ | ❌ |
| Load a convention when the agent reads or edits a file in a folder or of a type | ❌ | ❌ | ✅ | ❌ | ❌ |
| Load a procedure when the agent judges the task needs it | ❌ | ❌ | ❌ | ✅ | ❌ |
| Block a tool call that meets a condition, before it runs | ❌ | ❌ | ❌ | ❌ | ✅ |

## 🧭 Use cases

Ask Claude Code for a cue in plain words; the `context-cue` skill builds and tests it. All three below are in [`examples/`](examples), with their tests.

### Read a tool's output the right way

> _"When you search with `tvly`, remind yourself how to read the scores."_

The cue fires after the first `tvly search` of a session, beside the results. The agent reads the top `score` before anything else, and treats a top score under about 0.1 as a failed search.

### Keep comments short

> _"When a commit is mostly comments, remind me how we write them."_

The cue fires after the first commit of a session whose added lines are mostly comments, in any language cloc counts. It says why it fired and gives the rules: comments explain why, in one line where one will do, even where the repository's own conventions differ.

### Stop a habit in one kind of repository

> _"In repos with no remote, don't offer to push."_

The cue fires after the first commit in a repository with no remote, once for each such repository, so the agent's report ends at the commit.

## ⚠️ Limits

- **The cue arrives just after the first act, not before it.** Context from a `PreToolUse` hook also reaches the agent beside the tool result, so it lands no sooner. The first act of a session goes unguided; every later one is covered.
- **Subagents do not get cues.** A subagent shares its parent's `session_id`, so a cue that fired for the parent counts as fired for the subagent, which never saw the text.
- **A command cue can fire on a mention.** It matches a command wherever a shell could run it, but it cannot tell when that spot is inside quotes. `echo "done; tvly search next"` fires a `tvly search` cue, and so does a heredoc line that starts with `tvly search`.
- **Cue text is capped at 10,000 characters** by Claude Code. Longer output is cut to a preview of the first 2,000 characters, so a long cue should point to a doc instead.

## 📐 Cue specification

A cue is a folder with two small files: `cue.ini` says when it fires, and `prompt.md` holds the text. The `context-cue` skill walks the agent through a new cue: write `prompt.md`, choose the checks in `cue.ini`, list fired and silent cases in `tests.json`, say what the cue is for in a short `README.md`, run them with the skill's `cue-test.sh`, and move the folder into `~/.claude/context-cues/`.

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

## 📂 Examples

One example per kind of check, each a cue the author runs.

| Example | Fires on | Shows |
| --- | --- | --- |
| [`tvly-search`](examples/tvly-search) | the first `tvly search` a session runs | `command`, and extending a third-party skill |
| [`comment-slop`](examples/comment-slop) | the first commit of a session whose added lines are mostly comments, counted by cloc | `run` calling a tool of its own, named in the cue's README, and `${SHARE}` in the prompt |
| [`worktree-base`](examples/worktree-base) | the first subagent a session starts in its own git worktree | `tool-input`: one field of the call's input |
| [`no-remote`](examples/no-remote) | the first commit in a git repository with no remote, once per repository | `run`, a key per repository, and `${REPO}` in the prompt |
| [`agent-docs`](examples/agent-docs) | the first write to a skill, `AGENTS.md` or `CLAUDE.md`, unless the writing skill it points to is already loaded | `[suppress]`, and `exclude` |

## ⏱️ Cost

No tokens until a cue fires. One hook process starts after each call of a tool some cue checks (Bash, PowerShell, the file-editing tools, Agent and Skill); Read, Grep and Glob start nothing. Measured inside Claude Code on Linux, it adds about 5 ms to such a call with no cues installed, and about 17 ms to a Bash call with the five examples. [`docs/performance.md`](docs/performance.md) has the measurements.

## ⚙️ How it works

One `PostToolUse` hook, `dispatch.sh`, runs after each call of a tool some cue checks (Bash, PowerShell, the file-editing tools, Agent and Skill) with the call's JSON payload on stdin: `session_id`, `tool_name`, `tool_input` and `tool_response`. Your cues live in `~/.claude/context-cues/`, one folder each, and a new folder is live on the next tool call. For each cue folder it goes through four steps:

1. **Already fired?** It skips a cue whose marker file exists at `$XDG_RUNTIME_DIR/context-cues/<session_id>/<cue-name>`.
2. **Right tool?** It reads every `cue.ini` and exits when no cue can act on this tool, so a `Read` or `Grep` call costs no `jq` run.
3. **Checks.** One `jq` run pulls out what the call itself names and adds: `file_path`, `new_string`, `content`, `command`. Each `[check]` section in `cue.ini` must pass, in order. A command check matches the command only where a shell would run it, so a commit message that mentions the command stays silent.
4. **Fire.** It writes the marker and prints `{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": "<prompt.md>"}}`. Claude Code shows the text to the agent as a system reminder beside the tool result. When several cues fire on one call, their texts arrive in one reminder, in the order of their folder names.

A cue fires again after `/compact` or `/clear`, when its text has been lost: `rearm.sh`, a `SessionStart` hook, deletes the session's markers.

A cue that is broken, such as one with a pattern that does not compile, stays silent and is named in `$XDG_RUNTIME_DIR/context-cues/errors.log`. The other cues keep working.

_Written with [Claude Code](https://claude.com/claude-code) and reviewed by the author._
