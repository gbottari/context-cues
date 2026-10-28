# no-remote

Stops the agent offering to push the first time it commits in a git repository with no remote, once for each such repository, and names the repository in the text.

`has-no-remote.sh` finds the repository from `git -C <dir>`, then a `cd <dir>` in the command, then the session's working directory, and returns it as the key that makes the cue fire once per repository.
