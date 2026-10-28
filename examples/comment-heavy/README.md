# comment-heavy

Tells the agent how to write comments the first time in a session that a commit's added lines are mostly comments, in any language [cloc](https://github.com/AlDanial/cloc) counts.

It fires after a `git commit` that adds at least 5 comment lines making up at least 30% of the comment and code lines it adds; `MIN_COMMENT` and `MIN_SHARE` at the top of `comment-share.sh` set both. Lines the commit rewrites count with the lines it adds, and a first commit is compared with an empty tree.

Needs `cloc` on `PATH`. Without it the cue stays silent. Install it with your package manager: `pacman -S cloc`, `apt install cloc`, `brew install cloc` or `choco install cloc`.
