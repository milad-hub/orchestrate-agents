# Architecture

**Spec:** [architecture.md](../templates/orchestrator-spec/architecture.md),
[generation-plan.md](../templates/orchestrator-spec/generation-plan.md),
[agents/](../templates/orchestrator-spec/agents/)

The role table, the flow, the parallelism limits and the trust boundaries live
in the spec. This page explains the shape around them.

## One spec, two generators

`templates/orchestrator-spec/` is platform-neutral and is the only place
behavior is authored. Each supported CLI has a generated tree — Claude Code in
`templates/agents/` and `templates/skills/`, Codex in `templates/codex/`.

Platform syntax lives only in a platform tree. The spec never contains a
`tools:` line or a `sandbox_mode`, because the moment it does, adding a third
platform means editing the spec rather than adding a generator.

The cost is real: every behavior change lands in three places. That is what
[check-drift.py](../tests/check-drift.py) exists to police — it compares
heading structure, numbered-step counts and status vocabulary between the two
trees, so a change that reached one and not the other fails rather than
shipping.

## Configuration is data; invariants are code

`orchestration.json` holds every user-settable value.
[verify-install.py](../templates/orchestrator-spec/verify-install.py) holds
every rule about those values.

This split is the load-bearing decision in the project. Prose describes a rule;
only the verifier enforces one. A constraint that is not in the verifier does
not exist — it is a sentence people will read once.

Consequence for contributors: a change that introduces a rule teaches the
verifier to check it *in the same change*, or the rule lasts until the first
person who did not read the prose.

## Settings fan out, and must agree

Model and effort appear in agent frontmatter, in `orchestration.json` and in
the README configuration table. The test-write flag reaches three JSON keys and
the validator's tool allowlist.

Anything writing one copy writes all of them. This is why
[config-ui.py](../templates/orchestrator-spec/config-ui.py) exists rather than
a note saying "edit these four files", and why it re-runs the verifier after
every write and rolls back on failure.

## Permissions are held by the harness

A delegate cannot do what its allowlist omits. Prompts describe intent;
allowlists and permission policy enforce it.

This is why the roles are shaped as they are: the researcher and judge have no
`Edit`/`Write` at all, so "read-only" is a property of the install rather than
a promise in a prompt. Widening either is a deliberate act, never a default —
see [policies/permissions.md](../templates/orchestrator-spec/policies/permissions.md).

## The manager runs as the session

Subagents cannot spawn subagents on either platform. A manager spawned as a
delegate would therefore lose its entire pipeline — which is exactly what
happened in the first live run, and is why `/orchestrate` makes the current
session adopt the manager role instead of spawning one.

## What the knowledge layer added

The knowledge tree, its manifest, the repository profile, skills, the agent
registry and the proposal gate all arrived after the shape above was settled,
and none of them changed it: knowledge is spec data, its enforcement is
verifier code, its settings fan out like every other setting, and its
permissions are held the same way.

That is the test of whether the structure is right — a large feature that
needed no structural exception.

## Standing technical debt

Named rather than discovered later. None of these is a defect to fix; each is a
cost the current shape accepts.

**Two-generator duplication.** Every behavior change lands in the spec and both
platform trees. `check-drift.py` makes divergence fail rather than ship, but it
cannot remove the work — and a third platform makes it a third. The mitigation
is keeping descriptors declarative so generation stays mechanical; the
alternative, a real templating engine, would buy less than the runtime
dependency it costs.

**Markdown-only validation.** The verifier checks structure: schema,
references, agreement between copies. It cannot check meaning. Two rules can
each be well-formed and jointly incoherent, and nothing here will notice. The
human approval gate on proposals is the backstop, and it depends on people
reading them.

**Prompt contracts are not observed.** Several guarantees — the manager reusing
a stored profile, truncating at the knowledge budget — are enforced by prompt
text and checked only for presence, never for behavior. Packet slicing is now
half-observed: the verifier checks that the slicing table names real documents
and never narrows away a security-band one, but nothing observes whether the
manager honors the table it was given. See [testing.md](testing.md) for the
full list of what the harness cannot prove.
