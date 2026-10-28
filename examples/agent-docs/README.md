# agent-docs

Points the agent at the `mattpocock-skills:writing-for-agents` skill the first time in a session that it writes a document an agent reads: a `SKILL.md`, `AGENTS.md` or `CLAUDE.md`, a file in a skill folder, or a file under `.claude/agents`, `commands` or `rules`.

Loading that skill first spends the cue without a word, since the skill already says everything the cue would. Writes into a skill-creator `<skill>-workspace/` folder are skipped.

The prompt names a skill from the `mattpocock-skills` plugin; with a different writing guide, change the skill name in `prompt.md` and in the `[suppress]` section.
