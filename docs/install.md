# Installing Context Cues

Requirements: Claude Code, `bash`, `jq` 1.6 or later, and standard `awk`, `grep`, `sed` and `sort`. On Windows, Claude Code also needs Git for Windows, so hooks run in Git Bash; the README's Platforms section has the details.

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
