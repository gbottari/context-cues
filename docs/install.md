# Installing Context Cues

Requirements: Claude Code, `bash`, `jq` 1.6 or later, and standard `awk`, `grep`, `sed` and `sort`.

## Platforms

CI runs the full test suite on Linux, macOS and Windows for every push.

- **Linux and WSL:** install `jq` if your distribution lacks it.
- **macOS:** the tests pass with the system bash 3.2.57 and BSD grep. Install `jq` if your macOS version lacks it (`brew install jq`).
- **Windows:** the tests pass under the GitHub runner's bash. For real use, Claude Code needs Git for Windows, because it runs hooks in Git Bash when Git Bash is installed and in PowerShell when it is not. Install `jq` separately (`winget install jqlang.jq`). Commands the agent runs through the PowerShell tool reach hooks as `tool_name: "PowerShell"`, so a command check that should see them needs `tools = Bash|PowerShell`. The command-position check assumes bash syntax.

## The plugin

In a Claude Code session (2.1.275 or later):

```
/plugin install context-cues --marketplace gbottari/context-cues
```

From your shell, in one command (Claude Code 2.1.292 or later):

```bash
claude plugin install context-cues --marketplace gbottari/context-cues
```

Or in two steps:

```bash
claude plugin marketplace add gbottari/context-cues
claude plugin install context-cues@context-cues
```

The plugin brings the `context-cue` skill and registers the two hooks, `dispatch.sh` and `rearm.sh`. Your cues live in `~/.claude/context-cues/`, one folder each, and a new folder is live on the next tool call, with no settings to edit.

## An example cue by hand

The `context-cue` skill builds and tests cues for you. To install one of the repository's examples instead, copy its folder:

```bash
git clone https://github.com/gbottari/context-cues.git
mkdir -p ~/.claude/context-cues
cp -R context-cues/examples/tvly-search ~/.claude/context-cues/
```

## Without the plugin

Copy the hooks and the skill, then register the two hooks in `~/.claude/settings.json`. The hooks get their own folder, so `~/.claude/context-cues/` holds only your cues:

```bash
git clone https://github.com/gbottari/context-cues.git
cd context-cues
mkdir -p ~/.claude/hooks/context-cues ~/.claude/context-cues ~/.claude/skills
cp hooks/*.sh ~/.claude/hooks/context-cues/
cp -R skills/context-cue ~/.claude/skills/
```

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash|PowerShell|Edit|Write|MultiEdit|NotebookEdit|Agent|Task|Skill",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/context-cues/dispatch.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "compact|clear",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/context-cues/rearm.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

A manual install that still keeps the hooks in `~/.claude/context-cues/`, beside the cues, works as is. To move it, copy the hooks to `~/.claude/hooks/context-cues/` as above, change the two `command` paths in `settings.json`, and delete the old `dispatch.sh`, `rearm.sh` and `command-position.sh` from `~/.claude/context-cues/`.

## Removing it

Turn the plugin off with `claude plugin disable context-cues@context-cues`, or remove it with `claude plugin uninstall context-cues@context-cues`. Either way your cues stay in `~/.claude/context-cues/`; delete that folder if you no longer want them. To silence one cue, move its folder out of `~/.claude/context-cues/`.

Without the plugin, delete the two hook entries from `~/.claude/settings.json`, then the hooks and the skill:

```bash
rm -r ~/.claude/hooks/context-cues ~/.claude/skills/context-cue
```
