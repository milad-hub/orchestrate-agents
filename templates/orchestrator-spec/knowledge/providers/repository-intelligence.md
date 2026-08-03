---
id: repository-intelligence
category: provider
title: Derived profile of the repository under work
applies: *
precedence: 45
---

# Repository intelligence provider

**Source:** the repository profile derived by `discovery/project-analysis.md`.
**Trust level:** derived.
**Refresh:** per run, subject to a staleness rule.

## What it provides

The picture of the repository that rule and skill applicability is matched against:
languages, frameworks, dependency graph, packages, modules, architectural layers, folder
structure, build tooling, CI, test frameworks, lint configuration and observed coding
conventions.

This is what makes `applies: typescript, angular` mean anything. Without a profile,
every technology-scoped document is either always selected or never selected, and both
are wrong.

## How it is derived

From what the repository already states about itself — lockfiles, workspace and build
configuration, CI definitions, formatter and analyzer settings — and from a
repository-memory index when one is available. Nothing here parses source code that
another tool already understands better.

## Persistence

The profile is written to `.orchestrate/project-profile.json` in the target repository,
so an unchanged repository is not re-analyzed on every run. Where repository writes are
not permitted, or the path is not writable, it is derived per run and held in memory —
that is the behavior, not a failure.

## Staleness

A derived fact is accurate when fresh and misleading when stale — this is the provider
most able to produce a confident wrong answer. A stored profile is revalidated against
the repository before use, and a profile that cannot be revalidated is recomputed rather
than trusted.

## Failure behavior

An undeterminable field is reported as unknown. It is never defaulted to a plausible
value: a guessed framework selects the wrong rules, and nothing downstream can tell the
guess from a finding.
