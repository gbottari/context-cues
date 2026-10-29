# comment-slop

Gives the agent the rules for comments the first time in a session that a commit's added lines are mostly comments, in any language [cloc](https://github.com/AlDanial/cloc) counts. It says why it fired, states the rules, and tells the agent to follow them even where the repository's own conventions differ; what to do about the commit is left to the agent.

It fires after a `git commit` that adds at least 5 comment lines and 5 code lines, with comments making up at least 30% of them; `MIN_COMMENT`, `MIN_CODE` and `MIN_SHARE` at the top of `comment-share.sh` set all three. The code floor keeps a commit that only edits comments, such as a docs pass, silent. Lines the commit rewrites count with the lines it adds, and a first commit is compared with an empty tree. Only a HEAD made in the last minute is counted, so a commit that failed does not get the previous commit scored in its place. It counts comments and does not judge them: a commit of short, useful comments can fire it, and one rambling comment in a large commit will not.

Needs `cloc` on `PATH`. Without it the cue stays silent. Install it with your package manager: `pacman -S cloc`, `apt install cloc`, `brew install cloc` or `choco install cloc`.

## Cost

Until the cue fires, a `git commit` costs about 150 ms when it changes a few lines. The count fetches each side of the commit in one `git archive`, so the number of files matters little: 0.31 s for a commit touching 300 small files, 0.37 s for one touching 48. The size of the changed files matters more, since cloc reads both versions of each in full: 0.57 s for a commit that rewrote 2,700 lines of a lockfile. A commit whose changed files, both versions together, come to more than 1 MB (`MAX_BYTES`) is not counted, which keeps the hook well inside Claude Code's 10-second limit at about a second per megabyte; the cue stays silent and armed for the next commit. Once it has fired, it costs nothing for the rest of the session. Any other Bash call costs about 5 ms more than with no cues installed. Measured on 2026-10-28 on Linux by timing `hooks/dispatch.sh` directly: 30 runs per case for the small commits, 3 for the large ones, medians.
