---
id: git
category: rule
title: Version control rules
applies: *
precedence: 50
---

# Git rules

Higher precedence than general coding rules: several of these protect work that cannot
be recovered once lost.

## Never destroy uncommitted work

Do not reset, checkout over, stash or clean a dirty working tree without explicit
approval in the current request. Uncommitted changes have no backup.

## Isolate writes

Implementation work happens in a worktree, and the manager inspects the diff before and
after integration. Concurrent edits to overlapping file scopes are forbidden regardless
of isolation.

## Never push unprompted

Pushing is outward-facing and effectively irreversible. Committing, branching, fixing
or finishing work is not permission to push, and permission granted once does not carry
to the next change.

## Do not rewrite shared history

No force-push, no rebase of a branch someone else may have, no amend of a commit that
has left the machine.

## Commit what the change is

One logical change per commit, with a message stating what changed and why. A commit
mixing a refactor with a fix cannot be reverted usefully.

## Do not bypass the hooks

No `--no-verify`, no disabling signing. A failing hook is a finding, not an obstacle.

## Never commit a secret

Credentials, tokens and connection strings do not enter version control, and a secret
committed by mistake is rotated rather than merely removed in a later commit.

## Read the state before acting

Current branch, default branch, dirty files and recent commits are known before any
git operation that changes something.
