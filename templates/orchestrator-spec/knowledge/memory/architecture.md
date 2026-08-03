---
id: architecture
category: memory
title: How the bundle is structured and why
applies: *
precedence: 30
---

# Architecture

The full role/flow description lives in `orchestrator-spec/architecture.md`. This
document records the *structural* decisions behind it — the ones an agent needs in
order to make a change that fits.

## One spec, many generators

`orchestrator-spec/` is platform-neutral. Each supported CLI has its own generated
tree. Platform syntax lives only in that CLI's tree; the spec never contains it.

Consequence: a behavior change lands in the spec, then in every generated tree. A
change that reaches one tree only is drift, and the drift checks fail it.

## Configuration is data, invariants are code

`orchestration.json` holds every user-settable value. `verify-install.py` holds every
rule about those values. Prose in a README describes a rule; only the verifier
enforces one, so a new constraint that is not in the verifier does not exist.

## Settings fan out, and must agree

Model and effort appear in agent frontmatter, in `orchestration.json` and in the
README table. The test-write flag appears in three JSON keys and in the validator's
tool allowlist. Anything that writes one copy must write all of them — this is why the
settings UI exists and why it re-runs the verifier after every write.

## Permissions are held by the harness

A delegate cannot do what its tool allowlist does not include. Prompts describe
intent; allowlists and permission policy enforce it. Widening either is a deliberate
act, never a default.

## Knowledge is read through a manifest

Agents resolve knowledge through `knowledge/index.json` rather than walking the tree,
so lookup is bounded and what was selected is reportable.
