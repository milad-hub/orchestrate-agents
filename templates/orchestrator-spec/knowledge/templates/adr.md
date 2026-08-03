---
id: adr
category: template
title: Architecture decision record skeleton
applies: *
precedence: 30
---

# Architecture decision record

Copy the block below into a new document. Replace every angle-bracketed part. Keep the
headings — the sections are what make records comparable to each other.

An ADR records a decision that constrains later work. If nothing later is constrained by
it, it is a note, not a decision.

---

## ADR &lt;number&gt; — &lt;decision, stated as a claim&gt;

**Status:** proposed | accepted | superseded by ADR &lt;number&gt;
**Date:** &lt;YYYY-MM-DD&gt;

### Context

What forced a decision. The constraints that were real at the time, including the ones
that have since gone away — a reader in a year needs to know why the obvious option was
not obvious then.

### Decision

What was decided, in the active voice, as one claim. Not a discussion.

### Alternatives considered

Each realistic option, and the specific reason it lost. An alternative with no stated
reason reads as one nobody thought about, and gets reopened.

### Consequences

What this makes easy, what it makes hard, and what it rules out. Include the costs
accepted knowingly — an ADR listing only benefits is advertising.

### Compliance

How a later change is checked against this decision: which test, which verifier check,
or which review step catches a violation. A decision nothing enforces decays.
