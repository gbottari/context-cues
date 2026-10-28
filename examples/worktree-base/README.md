# worktree-base

Warns the agent the first time in a session that it starts a subagent with `isolation: worktree`: the worktree starts from the repository's default branch, so files that exist only on the current branch are missing there.

The text assumes Claude Code's default `worktree.baseRef` of `fresh`. Under `head`, the worktree starts from the current commit and only uncommitted changes are missing, so reword `prompt.md` to match.
