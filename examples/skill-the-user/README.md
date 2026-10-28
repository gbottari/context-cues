# skill-the-user

Catches the first time in a session that the agent writes "Giulio" into a skill file, a `SKILL.md` or any `.md` under a `skills/<name>/` folder, and has it say "the user" instead.

A skill that is shared, such as on a team marketplace, is read by people other than its author, so a name in its text points at the wrong person. The name is the author's: put yours in `match` in `cue.ini` and in `prompt.md`.

It matches only the text a write adds, through Edit, Write or a Bash write, so a session that writes "the user" from the start never spends it, and neither does deleting the name. skill-creator `<skill>-workspace/` output is skipped.
