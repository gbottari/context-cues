# Context Cues

Context Cues are Claude Code hooks that inject one piece of guidance the first time a session does a given kind of work. This repository holds the shared hook helpers, the `context-cue` skill that teaches an agent to build a cue, two example cues, and their tests. `README.md` explains the mechanism.

## Layout

| Path | Installed to | What it is |
| --- | --- | --- |
| `.claude-plugin/` | the plugin cache | `plugin.json` and `marketplace.json`: the repo root is both the marketplace and its one plugin |
| `hooks/` | the plugin, or `~/.claude/hooks/context-cues/` by hand | `dispatch.sh` (the one PostToolUse hook, reading every cue folder), `rearm.sh` (SessionStart re-arm), `command-position.sh` (sourced by the dispatcher), `hooks.json` (registers both hooks for the plugin) |
| `skills/context-cue/` | the plugin, or `~/.claude/skills/context-cue/` by hand | The skill: `SKILL.md`, `scripts/cue-test.sh` (runs a cue folder's `tests.json` through the dispatcher), `references/trigger-design.md` |
| `examples/` | `~/.claude/context-cues/`, optional | One cue folder per kind of check: `cue.ini`, `prompt.md`, `tests.json`, and any run-step script |
| `tests/` | not installed | `dispatch-test.sh` for the dispatcher itself; `run.sh` runs it and every example's `tests.json` |
| `docs/` | not installed | `install.md`, every way to install beyond the README's plugin command; measurements behind the README's cost claims |

## Rules

Read `CONTRIBUTING.md` before changing a script, a cue, a test or a doc, and before committing: it holds the checks to run, the portability rules, the commit format and the Markdown rule. The rules below are the ones only an agent needs.

- **The skill folder is installed on its own.** Every file `SKILL.md` or its references point an agent at lives inside `skills/context-cue/`; a pointer into `examples/`, `tests/` or `docs/` breaks once installed. Link to the GitHub URL for anything outside it.
- **Develop against a scratch install.** Point `CONTEXT_CUES_DIR` at a temporary folder of cues and `XDG_RUNTIME_DIR` at another for the markers, as `cue-test.sh` does. The live `~/.claude` belongs to whoever runs the session, and an edit there changes their sessions.
- **Every example earns a feature.** Each example shows one kind of check or key, and is a cue someone runs. A feature with no example that needs it does not ship. The one exception is `match` on a `file-write` check, which `tests/dispatch-test.sh` covers.
- **A trigger change is proven red, then green.** Break the trigger on purpose, watch its matrix go red, then restore it and watch it go green. A matrix that stays green on the broken version tests nothing.
- **Cue text stays one short paragraph.** It lands mid-task; Claude Code cuts hook output past 10,000 characters to a preview.
- **Check the plugin with `claude plugin validate .`** after touching `.claude-plugin/` or `hooks/hooks.json`; CI checks only that the files parse and the names match.
- **Stage files by name** (`git add <path>...`) and commit one change at a time.
