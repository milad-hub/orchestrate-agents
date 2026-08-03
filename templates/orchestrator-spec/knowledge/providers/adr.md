---
id: adr
category: provider
title: Architecture decision records for the repository under work
applies: *
precedence: 55
---

# ADR provider

**Source:** decision records in the target repository — `docs/adr/`,
`doc/adr/`, `adr/`, `architecture/decisions/`, or wherever that repository
keeps them.
**Trust level:** curated.
**Refresh:** per run, discovered rather than configured.

## What it provides

The decisions a change must not silently contradict. An ADR is the record of a
choice that constrains later work; without one in context, each run
re-litigates settled questions and reaches a different answer than the last.

Precedence 55 — above general memory, below security. A decision recorded by
the repository's own team outranks this bundle's general guidance about the
same subject, because it is specific to that codebase.

## How it is discovered

By location and shape, not configuration: a directory of numbered markdown
files carrying Status, Context, Decision and Consequences headings. A
repository with no such directory has no ADRs, which is reported as a fact
rather than treated as an error.

`knowledge/templates/adr.md` is the shape this bundle writes when asked to
draft one. A repository with its own ADR format keeps it — the repository's
convention wins.

## Superseded records

An ADR marked superseded is loaded with that status attached, never silently
dropped. Knowing a decision was reversed, and by which record, is the thing a
later run most needs; a missing ADR reads as a question nobody asked.

## Write path

**Read-only, like every provider.** An architectural change may *propose* an
ADR, written to `.orchestrate/proposals/` and never into the repository's ADR
directory. A record nobody approved is not a decision — it is a suggestion
wearing the format of one, and the format is exactly what makes later runs
treat it as settled.

## Failure behavior

A malformed record is reported and skipped, not guessed at. A repository whose
ADRs live somewhere unusual is reported as "none found" rather than having a
location invented for it.
