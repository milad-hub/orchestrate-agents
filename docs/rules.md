# Rules

**Spec:** [knowledge/rules/](../templates/orchestrator-spec/knowledge/rules/),
[instructions/instruction-precedence.md](../templates/orchestrator-spec/instructions/instruction-precedence.md),
[instructions/instruction-governance.md](../templates/orchestrator-spec/instructions/instruction-governance.md)

Five rules ship: `coding`, `testing`, `git`, `architecture`, `security`. The
precedence order and the conflict-resolution procedure are in the spec files
above. This page explains the design.

## Why they are language-neutral

A rule that only makes sense for one stack goes in a technology-scoped document
with a narrower `applies`. The five shipped rules apply everywhere because the
bundle is installed once for every repository on the machine.

`rules/examples/` demonstrates the scoped form without asserting a stack. It is
excluded from the manifest, so no agent can select it.

## The precedence bands

| Band | For |
|---|---|
| 0–19 | Defaults anything may override |
| 20–39 | General guidance |
| 40–59 | Bundle rules as shipped |
| 60–79 | Technology-scoped rules |
| 80–100 | Security and safety |

Bands exist so a tie is broken by **specificity**, not load order. Load order is
not a decision anybody made, and a rule set whose behavior depends on it is a
rule set nobody can reason about.

`git` sits at 50 rather than 40 because several of its rules protect work that
cannot be recovered — uncommitted changes have no backup, and a push is
effectively irreversible.

The security band is enforced: `verify-install.py` refuses anything but a rule
or skill above 80. A template sitting there would outrank the security rules
while carrying none of their authority.

## What always wins

**The repository.** Its instruction files are level 4 in the governance order;
every knowledge document is below. A bundle rule contradicting the repository
the agent is working in is not applied, and the conflict is reported.

This bundle is the general case; the repository in front of the agent is the
specific one. Specific wins — the same principle as the bands, one level up.

**Restriction over permission.** A lower level may narrow a higher one, never
widen it. A document appearing to grant something the policy withholds is
reported, not obeyed.

## Conflicts between two rules

Precedence band, then specific over general (a matched applicability token
outranks `applies: *`), then category, then `id`. Deterministic, so the same
pair resolves the same way on every run.

The losing document is dropped **for that conflict only** — it still applies
wherever it does not contradict the winner.

Both the resolution and what it displaced are reported. A conflict resolved
silently is a rule that stopped applying without anyone noticing, which is the
failure mode this whole ordering exists to avoid.

An irreconcilable conflict at equal precedence *and* equal specificity is a
defect in the tree, not a runtime decision: the `id` tie-break keeps the run
deterministic and the conflict is reported for a human to fix.
