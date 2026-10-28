# comment-slop

Tells the agent how to write comments the first time in a session that a commit's added lines are mostly comments, in any language [cloc](https://github.com/AlDanial/cloc) counts.

It fires after a `git commit` that adds at least 5 comment lines making up at least 30% of the comment and code lines it adds; `MIN_COMMENT` and `MIN_SHARE` at the top of `comment-share.sh` set both. Lines the commit rewrites count with the lines it adds, and a first commit is compared with an empty tree. It counts comments and does not judge them: a commit of short, useful comments can fire it, and one rambling comment in a large commit will not.

Needs `cloc` on `PATH`. Without it the cue stays silent. Install it with your package manager: `pacman -S cloc`, `apt install cloc`, `brew install cloc` or `choco install cloc`.

## Cost

Every `git commit` costs about 200 ms until the cue fires, about 180 ms of it cloc itself; once it has fired, nothing for the rest of the session. Any other Bash call costs about 7 ms more than with no cues installed. Measured on 2026-10-28 on Linux by timing `hooks/dispatch.sh` directly in a shell loop, 30 runs per case in shuffled order, medians, on a 2-line and a 7-file commit that stayed under the threshold.
