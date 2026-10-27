# Contributing

Thanks for looking. Context Cues is a small project maintained by one person in spare time. Issues and pull requests are welcome; it is provided as is, and no response time is promised.

## Check a change

Run the tests and the linters before opening a pull request. CI runs the same checks on Linux, macOS and Windows.

```bash
bash tests/run.sh
shellcheck -x hooks/*.sh examples/*/*.sh skills/context-cue/scripts/*.sh tests/*.sh
npx prettier@3.9.10 --check '**/*.md'
```

`tests/run.sh` runs `tests/dispatch-test.sh`, which checks the dispatcher itself: the `cue.ini` dialect, the run-step contract, two cues on one call, re-arming, and a broken cue staying silent without silencing the others. Then it runs each example's `tests.json` through the skill's `cue-test.sh`, the same tool the skill gives to agents: the cue is installed alone in a temporary folder, and each case is marked to fire or to stay silent.

A new or changed example needs fired-or-silent cases in its `tests.json`, which `skills/context-cue/scripts/cue-test.sh` runs: one case for each trap in `skills/context-cue/references/trigger-design.md`, plus once per session. A command cue gets the command matrix; `examples/tvly-search/tests.json` shows it. A change to the dispatcher gets a case in `tests/dispatch-test.sh`. Show a new case failing when you break the code it covers on purpose, since a case that cannot fail proves nothing.

## Keep the scripts portable

Cues run inside Claude Code on every call of a tool they check, on Linux, on macOS with the system bash 3.2, and on Windows under Git Bash.

- Write hooks in bash, with `jq` 1.6 or later and POSIX `awk` as the only other dependencies. No Python, Node or other runtimes in anything a user installs.
- Use portable `grep -E`. Spell word boundaries out, as in `(^|[^[:alnum:]_-])tee[[:space:]]`, because `\b`, `\w` and `grep -P` are missing from some grep builds.
- Keep the dispatcher cheap: it runs on every Bash call and every file edit. Check markers and the tool name before `jq`, and match short text with bash's `=~` rather than starting `grep`.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix(skill):`, `docs:`, `test:`, `refactor:`. The subject says what the change does; the body, when there is one, says why.

## Markdown

Write one line per paragraph and per list item, with no hard wraps. `.prettierrc.json` sets this, and CI fails on a wrapped paragraph. To fix a file, run `npx prettier@3.9.10 --write '**/*.md'`.

## AI-assisted contributions

Using AI tools is fine. When a substantial part of a change was written by one, say so in the pull request, and review and test the change yourself before asking for review: you are its author, and accountable for it. An `Assisted-by:` trailer in the commit message is welcome but not required. The project itself discloses its own AI use once, in the README.
