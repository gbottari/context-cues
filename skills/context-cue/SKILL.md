---
name: context-cue
description: Build a context cue — guidance a Claude Code hook injects into the agent's context the first time a session performs a given kind of work, then keeps silent for the rest of that session. Use when a rule written in CLAUDE.md or AGENTS.md would have faded by the time the work starts, when a path-scoped `.claude/rules` file would load on any read of a matching file rather than on the act, or the act is running a command or a write through Bash, when a per-edit hook would be noise, or to add guidance to a third-party skill without editing it; also when asked for a just-in-time or once-per-session reminder.
compatibility: Claude Code hooks; bash, awk and jq 1.6 or later
---

# Context cue

A **context cue** is guidance that reaches the agent _when the work it governs begins_: not at session start, where it competes with everything else and fades before it is needed, and not on every edit, where it becomes noise. It has three parts: **checks** on the tool call, a per-session **marker** so it fires once, and the **prompt** it injects as `additionalContext`.

Each cue is a folder, `~/.claude/context-cues/<name>/`:

| File | What it holds |
| --- | --- |
| `cue.ini` | the checks: when the cue fires |
| `prompt.md` | the text the agent reads; `${VAR}` takes a value from a run step |
| `tests.json` | the fired-or-silent cases [`cue-test.sh`](scripts/cue-test.sh) runs |
| any script | a run step's script, named in `cue.ini` |

One hook, `dispatch.sh`, reads every folder on every tool call. With the Context Cues plugin it is registered already; a manual install registers it once in `~/.claude/settings.json`, under `PostToolUse` with the matcher `*`. A new cue needs no settings change: the folder is live as soon as `cue.ini` exists, so build it elsewhere and move it in once its tests pass.

**Hook on the act, not on the skill.** A cue about a tool that a skill teaches could fire when the `Skill` tool loads that skill, but agents often run the tool without loading the skill (in the author's sessions, one CLI ran without its skill in 12 of 22 sessions), and a skill invoked as a slash command bypasses the `Skill` tool entirely. A cue about _doing_ something watches the doing. The same property lets a cue extend a third-party skill: the guidance lives in the cue, so the skill's own files stay untouched and its updates pull cleanly.

It is a cue, not a `.claude/rules` file: a path-scoped rule loads on the first read, write or edit of a matching file, whatever the work, and has no trigger for running a command or for a write through a Bash redirect ([trigger-design.md](references/trigger-design.md)); a rule with no `paths:` loads in every session.

## Placement

Guidance reaches the agent one of three ways, and the axis is whether its relevance survives the distance from where it loads: `AGENTS.md` or `CLAUDE.md` is always present and fades as the session grows; a skill loads on a trigger, so it arrives already relevant; a hook fires at the tool call, where it neither fades nor can be reasoned away.

Keep a rule in `AGENTS.md` or `CLAUDE.md` when it holds for most of the work in the tree, or when the act that needs it leaves no clean signature to match. A high base rate pays for the always-on cost, and a weak trigger misfires. A rule about handling a repo's core data, in a repo where most work touches that data, stays there on both counts.

A context cue earns its place on the opposite profile: narrow scope, crisp trigger, and a real cost to the agent missing it.

## Steps

Build the folder in a scratch directory, `<scratch>/<name>/`; the folder name is the cue's name.

1. **Write `prompt.md`.** One short paragraph: the target behaviour, stated positively, and where fuller material lives. Done when the text reads as a standing rule, not as a complaint about one edit.
2. **Write `cue.ini`**: one `[check]` section per condition, from the built-ins below. Every check must pass, in order, and the first that fails stops the rest. Done when the checks name the act, not the file type: [trigger-design.md](references/trigger-design.md) has the five ways a trigger fires on the wrong call.
3. **Write `tests.json`**: one case per trap in [trigger-design.md](references/trigger-design.md), each fired or silent. The header of [`cue-test.sh`](scripts/cue-test.sh) shows the format. A command cue gets the command matrix, which covers every way a shell runs the command, every mere mention, and once per session; add one case per near miss of your own. A file-write cue gets the act through Edit, Write, MultiEdit and a Bash redirect (fired), and deleting the text, editing beside text already there, only reading a matching file, and a lookalike path (silent). Add the same `session` twice to check the marker.
4. **Run `bash <skill dir>/scripts/cue-test.sh <scratch>/<name>`.** Then break a check on purpose and watch a case fail: a test that stays green on a broken check tests nothing. Done when it reports ok, and went red on the broken check.
5. **Move the folder into `~/.claude/context-cues/`.** Moving it is a change to the user's sessions they approve; when the move is denied, hand back the folder's path and stop. Then the live check: in a fresh session, perform the act and confirm the prompt arrives as a system reminder (`claude --debug` logs hook output). Done when the reminder is observed in a live session, not reasoned about.

## cue.ini

```ini
# comments are whole lines starting with # or ;
[suppress]
uses = tool-input
tools = Skill
field = skill
match = ^my-plugin:the-skill-this-cue-would-repeat$

[check]
uses = file-write
path = \.tsx?([^[:alnum:]._-]|$)
match = (^|[^:])//|/\*
```

A value runs raw to the end of the line, so a pattern needs no quoting or escaping beyond its own; trailing blanks are trimmed, so write `[[:space:]]` for a trailing space. Patterns are POSIX extended regular expressions (`grep -E`): no `\b`, `\w` or `\d`.

| `uses =` | Passes when | Keys |
| --- | --- | --- |
| `command` | a Bash call runs the command, at command position: a mention in an argument, message or path stays silent | `match`: the command, such as `tvly[[:space:]]+search([[:space:]]\|$)`; `wrappers`: what it is run behind beyond `time`, `env` and the like, such as `npx\|pnpm[[:space:]]+exec`; `tools`: default `Bash`, or `Bash\|PowerShell` |
| `file-write` | the call writes a file matching `path`, through Edit, Write, MultiEdit, NotebookEdit or a Bash redirect, `tee` or `sed -i`, and adds a line matching `match` that was not there | `path`, anchored to the end of a path token; `match`: optional, any new line when left out; `exclude`: paths and commands to skip |
| `tool-input` | the call is one of `tools`, and its input matches | `tools`, such as `Agent\|Task`; `field`: one key of the tool input, or the whole input as JSON when left out; `match` |

**A run step**, `run = <script>`, takes the place of `uses` for a condition no built-in can check: a repository's remotes, a file on disk. The script sits in the cue folder and gets the hook payload on stdin, with `CUE_NAME`, `CUE_SESSION_ID` and `CUE_DIR` in its environment. Exit 0 passes, 1 does not, and anything else is an error. On a pass it may print `{"key": "...", "vars": {"NAME": "..."}}`: a key makes the cue fire once per session for each key instead of once, and each var fills `${NAME}` in `prompt.md`. Put a run step after the built-ins, so it runs only on calls they let through.

**A `[suppress]` section** takes the same built-ins and run steps. When one matches, the cue is spent for the session without a word: the case where the agent already has what the cue would say, such as having loaded the skill the cue points to.

## Reference

- **Payload fields** (`code.claude.com/docs/en/hooks.md`): every event carries `session_id`; `SessionStart` carries `source` ∈ `startup|resume|clear|compact|fork`; a tool event carries `tool_name`, `tool_input`, `tool_response` and `cwd`. `additionalContext` from `PreToolUse` or `PostToolUse` arrives beside the tool result, so a cue lands just after the act.
- **A broken cue** (a pattern that does not compile, an unknown key, a missing `prompt.md`, a run step that exits 2 or more) stays silent, and its line in `$XDG_RUNTIME_DIR/context-cues/errors.log` names it. The other cues are unaffected. `cue-test.sh` fails on any line there.
- **Re-arming.** `rearm.sh` clears a session's markers on `compact` and `clear`, the two moments injected context is lost, so every cue can fire once more.
- **Subagents** share the parent's `session_id` but not its context. A cue fired in the parent never reaches a subagent, and the marker keeps it from firing there; `SubagentStart` is the event to deliver it to subagents if that matters.
- **Output cap** is 10,000 characters per hook; longer text is spilled to a file and replaced by a preview of the first 2,000 characters. A cue that needs more keeps its text in a doc and points to it.
- **Windows.** Hooks run in Git Bash when Git for Windows is installed, and cannot run the dispatcher without it. Commands the agent runs through the PowerShell tool reach hooks as `tool_name: "PowerShell"`; set `tools = Bash|PowerShell` on a command check that should see them, knowing the command-position check assumes bash syntax.
