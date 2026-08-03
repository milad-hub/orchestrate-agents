---
id: feature
category: template
title: Feature description skeleton
applies: *
precedence: 30
---

# Feature

Copy the block below. Replace every angle-bracketed part. The acceptance criteria
section is the one that must not be skipped — the orchestration workflow refuses to
delegate work whose success cannot be measured.

---

## &lt;Feature name&gt;

### Problem

Who is blocked, and by what. Stated without naming a solution. A problem statement that
already contains the answer has skipped the part where alternatives exist.

### Outcome

What is true once this ships that is not true now, from the user's side.

### Scope

**In:** &lt;what this change covers&gt;
**Out:** &lt;what it deliberately does not, and why&gt;

The out-list is the useful half. It is what stops the work growing while nobody is
looking.

### Acceptance criteria

Numbered, each independently checkable, each naming how it is verified — a command, a
test, an observable behavior. "Works correctly" is not a criterion.

1. &lt;criterion&gt; — verified by &lt;command or test&gt;
2. &lt;criterion&gt; — verified by &lt;command or test&gt;

### Affected areas

Files, modules and boundaries this touches. Anything shared gets its callers checked
before it is changed.

### Risks

What could break that is not obviously related, and what would make this hard to
reverse.
