---
id: design
category: template
title: Design document skeleton
applies: *
precedence: 30
---

# Design

Copy the block below. Replace every angle-bracketed part.

A design document is written before the work, to be argued with. If it is written after,
it is documentation — useful, but it cannot change the outcome.

---

## &lt;Design title&gt;

### Goal

What this design has to achieve, in one paragraph. If it takes three, the design covers
more than one thing.

### Constraints

What is fixed and not up for negotiation: compatibility, performance floors, security
requirements, deadlines, existing decisions recorded in ADRs.

### Approach

The design itself. Structure, boundaries, data flow, and where each responsibility sits.
State the seams — the places a later change is expected to plug into.

### Alternatives

Each option considered, and the specific reason it lost. Include the simplest option
that could have worked, even when it lost, because reviewers will ask.

### Trade-offs accepted

What this design is deliberately bad at. Every design is bad at something, and naming it
is what separates a decision from an assumption.

### Failure modes

What happens when a dependency is unavailable, input is malformed, or the operation is
interrupted halfway.

### Migration

How the system gets from where it is to this design, and whether the two can coexist. A
design with no path from the present is a rewrite in disguise.

### Verification

How anyone confirms this was built as designed: tests, checks, observable behavior.
