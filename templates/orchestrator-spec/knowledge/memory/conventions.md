---
id: conventions
category: memory
title: How work is done in this bundle
applies: *
precedence: 40
---

# Conventions

House conventions for changing this bundle. These are not general engineering advice —
each one exists because ignoring it has a specific, known cost here.

## Change the spec first

A behavior change starts in `orchestrator-spec/`, then reaches every generated tree.
Editing a generated file directly means the next regeneration silently reverts it.

## Ship the invariant with the feature

If a change introduces a rule, the same change teaches `verify-install.py` to check it.
A rule enforced only by prose lasts until the first person who does not read the prose.

## Fan out completely, or not at all

A setting that lives in several files is written to all of them in one change. Half a
fan-out is worse than none: the verifier fails, and the failure points at the file that
was correct.

## Prefer restriction to instruction

When a delegate must not do something, remove the tool rather than adding a sentence
telling it not to. Allowlists hold; sentences persuade.

## No placeholders

A stub ships only when the content is genuinely per-repository, and it says so in its
own text. A file whose body is "TODO" is a promise nobody tracks.

## Documentation is part of the change

User-visible behavior updates `README.md` and the installed `README-orchestration.md`
in the same change, because a stale line gets trusted and acted on.

## Both platforms, both suites

A change is finished when both smoke suites pass, not when one does. The two do not
test the same paths.

## Small, verifiable steps

Each change leaves the bundle installable and verifiable. Work that cannot be verified
until three changes later is work nobody can review.
