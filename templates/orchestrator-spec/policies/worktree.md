# Worktree Policy

- Implementation workers run with worktree isolation when supported:
  the manager spawns them via the Agent tool with `isolation: "worktree"`.
  Claude Code creates a temporary git worktree (isolated repo copy);
  worktrees left unchanged are auto-cleaned.
- Why: parallel workers cannot clobber each other or the user's dirty
  working tree; failed attempts leave no residue.
- Parallel write work still requires disjoint file scopes even with
  worktrees — disjoint scopes keep integration trivial and conflict-free.
- Integration: after a worker reports COMPLETE, the manager inspects the
  worktree diff, then integrates changes into the session's working tree
  (harness-assisted integration when offered; otherwise explicit
  `git diff`/`git apply` or merge of the worktree branch). The manager
  re-inspects the final integrated diff — integration is part of the
  manager compliance gate.
- Conflicts on integration: manager resolves only trivial, mechanical
  conflicts itself; anything semantic goes back to a worker as a narrow
  correction task.
- Researcher/judge don't need worktrees (read-only). Validator normally
  runs in the integrated tree so it validates what will actually ship; it
  may use a worktree when its test edits must stay quarantined.
- Workers report worktree integration status; judge verifies no work was
  lost between worktree and final tree.
