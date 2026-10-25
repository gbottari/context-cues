# Contributing

Thanks for looking. Context Cues is a small project maintained by one person in spare time. Issues and pull requests are welcome; it is provided as is, and no response time is promised.

## Check a change

Run the tests and the linters before opening a pull request. CI runs the same checks on Linux, macOS and Windows.

```bash
bash tests/run.sh
shellcheck -x hooks/*.sh examples/*/*.sh skills/context-cue/*/*.sh tests/*.sh
npx prettier@3.9.10 --check '**/*.md'
```

A new or changed cue needs fired-or-silent test cases built with `skills/context-cue/scripts/cue-test.sh`: one case for each trap in `skills/context-cue/references/trigger-design.md`, plus once-per-session and re-arming. A command cue gets `command_matrix` and `rearm_check`; `tests/command-cue-test.sh` shows both. A change to a trigger should also be shown to fail its matrix when you break the trigger on purpose, since a matrix that cannot fail proves nothing.

## Keep the scripts portable

Cues run inside Claude Code on every tool call, on Linux, on macOS with the system bash 3.2, and on Windows under Git Bash.

- Write hooks in bash, with `jq` 1.6 or later as the only other dependency. No Python, Node or other runtimes in anything a user installs.
- Use portable `grep -E`. Spell word boundaries out, as in `(^|[^[:alnum:]_-])tee[[:space:]]`, because `\b`, `\w` and `grep -P` are missing from some grep builds.
- Keep hooks cheap: a reject-only grep over the raw payload first, then the marker check, and only then `jq`.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix(skill):`, `docs:`, `test:`, `refactor:`. The subject says what the change does; the body, when there is one, says why.

## Markdown

Write one line per paragraph and per list item, with no hard wraps. `.prettierrc.json` sets this, and CI fails on a wrapped paragraph. To fix a file, run `npx prettier@3.9.10 --write '**/*.md'`.

## AI-assisted contributions

Using AI tools is fine. When a substantial part of a change was written by one, say so in the pull request, and review and test the change yourself before asking for review: you are its author, and accountable for it. An `Assisted-by:` trailer in the commit message is welcome but not required. The project itself discloses its own AI use once, in the README.
