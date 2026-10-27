# What cues cost

Hook behaviour changes between Claude Code releases, so treat these figures as snapshots.

## Tokens

None until a cue fires. A cue that fires adds its text once, and again after each `compact` or `/clear`.

## Time

**Measured inside Claude Code on 2026-10-26**, with Claude Code 2.1.310 on Linux: the median gap between a tool call finishing and the next model request, which holds every `PostToolUse` hook. Each setup ran three headless sessions of 10 Bash calls (`echo N`) and 10 Read calls, in shuffled order, with only the test settings loaded. Within one setup, the median of a session moved by 2 to 3 ms.

| Setup | Bash call | Read call |
| --- | --- | --- |
| No hooks | 13.0 ms | 17.0 ms |
| The dispatcher, no cues | 18.0 ms (+5) | 21.0 ms (+4) |
| The dispatcher, the five examples | 30.0 ms (+17) | 24.0 ms (+7) |
| Four of the examples as v0.1 scripts, one hook each | 23.0 ms (+10) | 15.0 ms (none) |

**The plugin starts the dispatcher only after the tools some cue checks**: Bash, PowerShell, the file-editing tools, Agent and Skill. Read, Grep and Glob start nothing; the Read column shows what they would cost with the matcher `*`. With no cues installed the dispatcher adds about 5 ms to a call, and with the five examples about 17 ms to a Bash call. Claude Code reported the dispatcher itself at a median of 17 ms on a Bash call and 10 ms on a Read call. The dispatcher now keeps its parse of every `cue.ini` between calls; one more session with that cache put the hook at 15 ms on a Bash call and 6 ms on a Read call.

**One script per cue cost less per Bash call with four cues**, and nothing on a tool no cue watched: Claude Code starts a hook only for the tools its matcher names, and starts the hooks on one call in parallel. That layout grows with the number of cues: on 2026-10-10, with Claude Code 2.1.296, seven such hooks on `Bash` added 17.5 ms per call.

A call starts at most three processes: bash, one `jq`, and one `awk` that parses every `cue.ini`, only when one has changed since the last parse. A call no cue can act on stops before `jq`. Short text is matched with bash's own regex instead of `grep`, which saves a process per check; text of 2,000 characters or more goes to `grep`, because bash reads it a byte at a time. In a shell loop, a Bash call writing a 2,000-line heredoc, a 90 KB payload, took about 56 ms.

Windows and macOS were not measured. Starting processes under Git Bash on Windows is slower than on Linux, so expect a larger figure there.

## The handler `if` field

Claude Code's hook handlers take an `if` filter, such as `Bash(tvly search *)`, that skips spawning the hook at all. It is free and it works, but it recovered little here: with every cue filtered the gap was 12.0 ms, about 4 ms better than none, close to the noise. It also changes what matches:

- It spawns for the plain command, after `&&`, after a pipe, after `;`, inside `$()`, behind a leading `VAR=value`, in a subshell, behind `xargs`, and with no arguments.
- It stays silent for a mention inside quotes: `echo "…"`, a grep pattern, a `printf` argument, `python3 -c '…'`, text after `;` inside quotes.
- It misses a wrapped run: `time cmd`, `timeout 5 cmd`, `env FOO=1 cmd`, `bash -c 'cmd'`.
- It fires on an unquoted heredoc whose body line starts with the command.
- It cannot see a redirect target: `Bash(*out*)` did not match `echo hi > out/x.txt`, so a file-write cue cannot use it.

The dispatcher cannot use it: one hook serves every cue, so it has to see every call of the tools they check.

## Trigger styles

Over 9 real runs and 9 mentions of `tvly search`:

| Style | Real runs missed | Mentions that fired |
| --- | --- | --- |
| Name anywhere it is not part of a longer word | 0 | 6 |
| Command position: line start, after `;` `&` `\|` `(` | 3 | 3 |
| Strict position: `(` only as `$(`, leading `VAR=value` allowed | 2 | 2 |

`command-position.sh` is the strict style plus a list of wrapper words (`time`, `env`, `timeout N`, shell keywords) and a per-cue list for wrappers such as `npx`.
