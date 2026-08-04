---
id: bug
category: template
title: Bug report skeleton
applies: *
precedence: 30
---

# Bug

Copy the block below. Replace every angle-bracketed part.

A report names a symptom. The fix addresses a cause. The two sections are separate here
because collapsing them is how a patch lands on the one code path that was reported
while every sibling path stays broken.

---

## &lt;Symptom, in one line&gt;

### Observed

What happened. Exact output, exact error text, exit code. Quoted verbatim, not
paraphrased — a paraphrased error is unsearchable.

### Expected

What should have happened, and what makes that the correct behavior: a specification, a
test, a documented contract, or a stated assumption.

### Reproduction

1. &lt;step&gt;
2. &lt;step&gt;

Including environment, versions and any state the steps depend on. A report nobody can
reproduce gets closed rather than fixed.

### Frequency and impact

Always, intermittently, or under a specific condition. Who is affected and how badly —
this is what decides whether the fix is now or next.

### Root cause

Filled in once found. The mechanism, not the location: which assumption was violated,
by what. Name every caller of the code involved, so the fix goes where all of them route
through.

### Fix

What changed, and why that is the smallest change that addresses the cause.

### Regression check

The test that fails before the fix and passes after. A bug fix without one invites the
same bug back.
