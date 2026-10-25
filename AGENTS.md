# Context Cues

Context Cues are Claude Code hooks that inject one piece of guidance the first time a session does a given kind of work. This repository holds the shared hook helpers, the `context-cue` skill that teaches an agent to build a cue, two example cues, and their tests. `README.md` explains the mechanism.

## Layout

| Path | Installed to | What it is |
| --- | --- | --- |
| `hooks/` | `~/.claude/context-cues/` | `rearm.sh` (SessionStart re-arm) and `command-position.sh` (sourced by command cues) |
| `skills/context-cue/` | `~/.claude/skills/context-cue/` | The skill: `SKILL.md`, `scripts/cue-test.sh`, `references/trigger-design.md`, `assets/` hook templates |
| `examples/` | `~/.claude/context-cues/`, optional | One folder per cue: `<name>.sh` beside `<name>.cue.md` |
| `tests/` | not installed | Fired-or-silent matrices over the examples and the command template |
| `docs/` | not installed | Measurements behind the README's cost claims |

## Rules

Read `CONTRIBUTING.md` before changing a script, a cue, a test or a doc, and before committing: it holds the checks to run, the portability rules, the commit format and the Markdown rule. The rules below are the ones only an agent needs.

- **The skill folder is installed on its own.** Every file `SKILL.md` or its references point an agent at lives inside `skills/context-cue/`; a pointer into `examples/`, `tests/` or `docs/` breaks once installed. Link to the GitHub URL for anything outside it.
- **Develop against a scratch install.** Copy `hooks/` and `examples/` into a temporary folder and redirect `XDG_RUNTIME_DIR`, as `tests/lib.sh` does. The live `~/.claude` belongs to whoever runs the session, and an edit there changes their sessions.
- **A trigger change is proven red, then green.** Break the trigger on purpose, watch its matrix go red, then restore it and watch it go green. A matrix that stays green on the broken version tests nothing.
- **Cue text stays one short paragraph.** It lands mid-task; Claude Code cuts hook output past 10,000 characters to a preview.
- **Stage files by name** (`git add <path>...`) and commit one change at a time.
