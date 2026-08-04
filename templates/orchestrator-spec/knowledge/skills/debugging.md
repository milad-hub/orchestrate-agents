---
id: debugging
category: skill
title: Find the cause of a failure
applies: *
precedence: 45
---

# Debugging

## Purpose

Locate the cause of an observed failure. Ends where `bug-fixing` begins: this
skill produces an identified cause and the evidence for it, not a patch.

Wrong choice when the cause is already known — go straight to the fix. Wrong
when nothing is actually failing: "this looks wrong" is a review, not a
defect.

## Prerequisites

- An observed failure: exact output, exit code, or a reproducible wrong result.
  A described failure nobody has seen is a hypothesis.
- Read access to the failing path and its dependencies.

## Required context

`coding` and `testing` rules; `architecture` when the failure crosses a module
boundary; the repository's `integrations` when an external system is in the
path — a failure there is usually about the boundary, not the code either side
of it.

## Execution steps

1. Reproduce, and record exactly how. An intermittent failure is recorded as
   intermittent, with the observed rate.
2. Write down what you expect to be true. Debugging is comparing that list
   against reality, and an unstated expectation cannot be contradicted.
3. Narrow by bisection, not by inspection order: cut the failing path in half
   and establish which half misbehaves.
4. Verify each assumption at the boundary you narrowed to — inspect real
   values rather than reasoning about what they should be.
5. Stop at the first thing that is definitely wrong, and confirm it explains
   the whole symptom. A cause that explains most of it is usually not the
   cause.
6. Check whether the same cause reaches other call sites.

## Expected outputs

- The cause, stated as a violated assumption with the evidence that shows it.
- The reproduction, exact enough for someone else to run.
- The path from cause to symptom.
- Other sites affected by the same cause.

## Validation checklist

- The reproduction was run, and its output is quoted verbatim.
- The stated cause accounts for every part of the symptom, not part of it.
- The claim was tested against real values, not inferred from reading.
- Alternative explanations that were ruled out are named, with how.

## Quality checklist

- Is this a cause or a coincidence that co-occurs with the failure?
- Would the symptom disappear if this were fixed, and nothing else change?
- Was the search narrowed by evidence, or by where it was convenient to look?
- Is the reproduction minimal enough to be useful?

## Completion criteria

- Cause identified and evidenced, or explicitly reported as not found with
  what was ruled out.
- Reproduction recorded.
- Blast radius stated: every site the cause reaches.
- No fix applied — that is the next skill, and conflating them loses the
  reviewable boundary between finding and changing.
