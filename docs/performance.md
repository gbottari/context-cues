# What cues cost

Measured on 2026-10-10 with Claude Code 2.1.296 on Linux, with seven cues registered on `Bash`. Hook behaviour changes between Claude Code releases, so treat the figures as a snapshot.

## Tokens

None until a cue fires. A cue that fires adds its text once, and again after each `compact` or `/clear`.

## Time

**Seven cues add 17.5 ms per Bash call.** That is the median gap between a Bash tool call finishing and the next model request, against 11.5 ms with no hooks. Each configuration ran 40 unrelated Bash calls: two headless sessions of 20, in shuffled order, with only the test settings loaded. Medians of runs within one configuration moved by 1.5 to 3.5 ms.

**Hooks on one call run in parallel**, per the hooks reference ("All matching hooks run in parallel"). The wall-clock is set by the slowest hook that spawns, so the cost does not grow by one hook's time per cue.

**A shell loop understates it.** Timed outside Claude Code, one hook rejecting at its prefilter took about 5 ms, and seven started together took 6.1 ms. Claude Code's own spawn path is slower: it reported 8 to 16 ms per hook.

Windows and macOS were not measured. Starting processes under Git Bash on Windows is slower than on Linux, so expect a larger figure there.

## The handler `if` field

Claude Code's hook handlers take an `if` filter, such as `Bash(tvly search *)`, that skips spawning the hook at all. It is free and it works, but it recovered little here: with every cue filtered the gap was 12.0 ms, about 4 ms better than none, close to the noise. It also changes what matches:

- It spawns for the plain command, after `&&`, after a pipe, after `;`, inside `$()`, behind a leading `VAR=value`, in a subshell, behind `xargs`, and with no arguments.
- It stays silent for a mention inside quotes: `echo "…"`, a grep pattern, a `printf` argument, `python3 -c '…'`, text after `;` inside quotes.
- It misses a wrapped run: `time cmd`, `timeout 5 cmd`, `env FOO=1 cmd`, `bash -c 'cmd'`.
- It fires on an unquoted heredoc whose body line starts with the command.
- It cannot see a redirect target: `Bash(*out*)` did not match `echo hi > out/x.txt`, so a file-write cue cannot use it.

The cues in this project leave `if` out, because missing a wrapped run costs more than 4 ms.

## Trigger styles

Over 9 real runs and 9 mentions of `tvly search`:

| Style | Real runs missed | Mentions that fired |
| --- | --- | --- |
| Name anywhere it is not part of a longer word | 0 | 6 |
| Command position: line start, after `;` `&` `\|` `(` | 3 | 3 |
| Strict position: `(` only as `$(`, leading `VAR=value` allowed | 2 | 2 |

`command-position.sh` is the strict style plus a list of wrapper words (`time`, `env`, `timeout N`, shell keywords) and a per-cue list for wrappers such as `npx`.
