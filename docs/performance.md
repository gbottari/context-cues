# What cues cost

Hook behaviour changes between Claude Code releases, so treat these figures as snapshots.

## Tokens

None until a cue fires. A cue that fires adds its text once, and again after each `compact` or `/clear`.

## Time

**The dispatcher is one process per tool call, whatever the number of cues.** Measured on 2026-10-26 on Linux, in a shell loop rather than inside Claude Code, with the five example cues installed and no marker set. The machine's load average was about 7, and repeated runs moved by 1 to 3 ms.

| Call                                                 | Per call    |
| ---------------------------------------------------- | ----------- |
| `Read`, which no example acts on                     | about 8 ms  |
| `Bash` running `ls -la`                              | about 15 ms |
| `Edit` of an unrelated file                          | about 15 ms |
| `Bash` writing a 2,000-line heredoc, a 90 KB payload | about 56 ms |

A call starts three processes: bash, one `awk` that reads every `cue.ini`, and one `jq`. A call no cue can act on stops before `jq`. Short text is matched with bash's own regex instead of `grep`, which saves a process per check; text of 2,000 characters or more goes to `grep`, because bash reads it a byte at a time.

**Claude Code adds its own cost per hook.** On 2026-10-10, with Claude Code 2.1.296 and the earlier layout of one script per cue, seven cues on `Bash` added 17.5 ms per call: the median gap between a Bash call finishing and the next model request, against 11.5 ms with no hooks. Hooks on one call run in parallel, per the hooks reference ("All matching hooks run in parallel"), and Claude Code reported 8 to 16 ms to spawn each one. The dispatcher has not been measured inside Claude Code.

Windows and macOS were not measured. Starting processes under Git Bash on Windows is slower than on Linux, so expect a larger figure there.

## The handler `if` field

Claude Code's hook handlers take an `if` filter, such as `Bash(tvly search *)`, that skips spawning the hook at all. It is free and it works, but it recovered little here: with every cue filtered the gap was 12.0 ms, about 4 ms better than none, close to the noise. It also changes what matches:

- It spawns for the plain command, after `&&`, after a pipe, after `;`, inside `$()`, behind a leading `VAR=value`, in a subshell, behind `xargs`, and with no arguments.
- It stays silent for a mention inside quotes: `echo "…"`, a grep pattern, a `printf` argument, `python3 -c '…'`, text after `;` inside quotes.
- It misses a wrapped run: `time cmd`, `timeout 5 cmd`, `env FOO=1 cmd`, `bash -c 'cmd'`.
- It fires on an unquoted heredoc whose body line starts with the command.
- It cannot see a redirect target: `Bash(*out*)` did not match `echo hi > out/x.txt`, so a file-write cue cannot use it.

The dispatcher cannot use it: one hook serves every cue, so it has to see every call.

## Trigger styles

Over 9 real runs and 9 mentions of `tvly search`:

| Style | Real runs missed | Mentions that fired |
| --- | --- | --- |
| Name anywhere it is not part of a longer word | 0 | 6 |
| Command position: line start, after `;` `&` `\|` `(` | 3 | 3 |
| Strict position: `(` only as `$(`, leading `VAR=value` allowed | 2 | 2 |

`command-position.sh` is the strict style plus a list of wrapper words (`time`, `env`, `timeout N`, shell keywords) and a per-cue list for wrappers such as `npx`.
