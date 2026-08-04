---
id: refactoring
category: skill
title: Change structure without changing behavior
applies: *
precedence: 40
---

# Refactoring

## Purpose

Improve the shape of existing code — naming, cohesion, duplication, coupling —
while its observable behavior stays identical.

Wrong choice when behavior must change: that is a feature or a fix, and mixing
either into a refactor produces a diff nobody can review, because every hunk
could be the one that changed something.

## Prerequisites

- A verification that passes **before** starting. Refactoring without one is
  rewriting and hoping.
- A stated reason: what is hard now that will be easier after. "Cleaner" is
  not a reason.
- File scope assigned and disjoint.

## Required context

`architecture`, `coding`, `conventions`, `testing`.

## Execution steps

1. Run the suite first and record it green. That recording is the only thing
   that will tell you whether behavior moved.
2. Name the specific improvement and the smallest change that achieves it.
3. Check every caller of what is being restructured, including dynamic and
   test callers.
4. Change structure in steps that each leave the suite green, rather than one
   large motion.
5. Re-run the suite after each step, and compare against the recording.
6. Read the final diff for behavior changes that slipped in — a reordered
   condition, a changed default, a swallowed error.

## Expected outputs

- The restructured code, behavior unchanged.
- Before-and-after suite output.
- A statement of what improved and what it cost.

## Validation checklist

- The same tests pass before and after, with the same count — not merely
  "green" both times.
- No test was modified to accommodate the new structure, unless the test was
  asserting the structure rather than the behavior; say so explicitly when it
  was.
- The diff contains no behavior change: no altered defaults, conditions,
  ordering or error handling.
- Public interfaces unchanged, or their consumers updated in the same change.

## Quality checklist

- Is the code actually easier to work with, or merely arranged differently?
- Did this remove duplication, or move it?
- Is the abstraction justified by cases that exist, not cases imagined?
- Is the diff small enough to review hunk by hunk?

## Completion criteria

- Behavior demonstrably unchanged: identical test results before and after.
- The stated improvement achieved, and named.
- No feature or fix smuggled in.
- Scope respected.
