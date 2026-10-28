# comment-slop

Tells the agent how to write comments the first time in a session that a commit's added lines are mostly comments, in any language [cloc](https://github.com/AlDanial/cloc) counts.

It fires after a `git commit` that adds at least 5 comment lines making up at least 30% of the comment and code lines it adds; `MIN_COMMENT` and `MIN_SHARE` at the top of `comment-share.sh` set both. Lines the commit rewrites count with the lines it adds, and a first commit is compared with an empty tree. It counts comments and does not judge them: a commit of short, useful comments can fire it, and one rambling comment in a large commit will not.

Needs `cloc` on `PATH`. Without it the cue stays silent. Install it with your package manager: `pacman -S cloc`, `apt install cloc`, `brew install cloc` or `choco install cloc`.

## Cost

Until the cue fires, a `git commit` costs about 150 ms when it changes 2 lines, and more as it touches more files: about 250 ms for one that renamed 7 files. Once it has fired, it costs nothing for the rest of the session. Any other Bash call costs about 5 ms more than with no cues installed. Measured on 2026-10-28 on Linux by timing `hooks/dispatch.sh` directly in a shell loop, 30 runs per case in shuffled order, medians, on commits that stayed under the threshold.
