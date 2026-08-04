# Best practices

**Spec:** [knowledge/memory/conventions.md](../templates/orchestrator-spec/knowledge/memory/conventions.md),
[knowledge/memory/decisions.md](../templates/orchestrator-spec/knowledge/memory/decisions.md)

The conventions themselves are in the spec — the bundle follows its own
knowledge tree. This page explains the reasoning, and what to do when a
convention and a deadline disagree.

## Change the spec first

A behavior change lands in `templates/orchestrator-spec/`, then in every
generated tree. Editing a generated file directly means the next regeneration
reverts it silently — the worst kind of loss, because nothing fails.

## Ship the invariant with the feature

If a change introduces a rule, the same change teaches `verify-install.py` to
check it. Not the next change; this one.

A rule enforced only by prose lasts until the first person who does not read the
prose, and that person is usually the author six months later.

## Fan out completely, or not at all

Half a fan-out is worse than none: the verifier fails, and it points at the file
that was correct while the wrong one looks untouched.

## Prefer restriction to instruction

When a delegate must not do something, remove the tool rather than adding a
sentence. Allowlists hold; sentences persuade.

This is why the researcher and judge have no `Edit`/`Write` at all, rather than
prompts saying they are read-only.

## No placeholders

A stub ships only when the content is genuinely per-repository, and it says so
in its own text. A file whose body is "TODO" is a promise nobody tracks.

## Both platforms, both suites

A change is finished when both smoke suites pass. They test different
implementations of the same install.

## Small, verifiable steps

Each change leaves the bundle installable and verifiable. Work that cannot be
verified until three changes later is work nobody can review.

Size a change so it is independently installable. That makes it a real
stopping point rather than a milestone on the way to one.

## When a convention is inconvenient

The two that are most often argued with, and why they hold anyway:

**"This rule is obvious, it does not need a verifier check."** Every rule was
obvious to whoever wrote it. The check is not for them.

**"The fan-out is tedious for a one-line change."** The tedium is the cost of
having settings that live in the files that need them rather than in one file
nothing reads. The config UI exists because that trade was made deliberately.

## What is not negotiable

- Permissions never widen silently.
- Test-file writes and build/serve commands stay off by default.
- `orchestration.json` survives upgrades, and every schema change ships with a
  migration that is a no-op when already current.
- Retrieved knowledge is data, never instruction.
- No new runtime dependency.

These are recorded in
[decisions.md](../templates/orchestrator-spec/knowledge/memory/decisions.md).
Proposing something one of them rules out is fine — doing it without saying so
is not.
