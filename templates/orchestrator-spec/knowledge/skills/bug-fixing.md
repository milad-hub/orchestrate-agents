---
id: bug-fixing
category: skill
title: Fix a defect at its cause
applies: *
precedence: 45
---

# Bug fixing

## Purpose

Turn a reported symptom into a fix at its cause, with a check that fails before
the fix and passes after.

Wrong choice when the cause is not yet known — that is `debugging`, and this
skill starts where that one ends. Wrong when the behavior was never
implemented: that is `feature-development`.

Higher precedence than feature work because the failure mode here is specific
and expensive: patching the one path a ticket named while every sibling path
stays broken.

## Prerequisites

- A reproduction, or an explicit statement that reproduction was not possible
  and what was done instead.
- The cause is identified. A fix aimed at a symptom is rework with extra steps.
- File scope assigned and disjoint.

## Required context

`coding`, `testing`, `conventions`; `security` when the defect touches
validation, authentication, or anything crossing a trust boundary — a bug
there is a vulnerability until shown otherwise.

## Execution steps

1. Reproduce, and record the exact command, output and exit code. A fix for
   something never observed is a guess.
2. Establish the baseline: which tests failed before the change. Blaming a
   change for a pre-existing failure costs a correction cycle; missing a new
   one ships a defect.
3. Confirm the cause by evidence, not by plausibility. Name the assumption that
   was violated, and by what.
4. Find every caller of the code involved. The fix belongs where all of them
   route through — one guard in the shared path, not a guard per caller.
5. Write the failing check first when test writes are permitted: it must fail
   for the reported reason, not merely fail.
6. Make the smallest change that addresses the cause.
7. Re-run the check and the surrounding suite. Confirm the new case passes and
   nothing else moved.

## Expected outputs

- The fix, in the shared path rather than at the call site, unless there is a
  stated reason otherwise.
- A regression check that fails without the fix, or a stated reason there is
  none.
- Before-and-after command output.
- Any sibling defect found while tracing, reported even when out of scope.

## Validation checklist

- The reproduction now succeeds where it previously failed, shown by output.
- The regression check fails with the fix reverted — state that this was
  actually tried, not assumed.
- The full suite for the affected area exits 0, compared against the baseline.
- No test was weakened, skipped or deleted to make anything pass.
- The diff contains no file outside the assigned scope.

## Quality checklist

- Is this the cause or the nearest visible symptom?
- Were the other callers checked, or only the one the report named?
- Is the fix smaller than the bug it removes?
- Does the regression check describe the behavior, so it survives a refactor?
- Is there a class of input the fix still does not handle, and is it named?

## Completion criteria

- Cause stated, with the evidence that identified it.
- Fix applied where all affected callers route through.
- Regression check present and demonstrated to fail without the fix, or its
  absence explained.
- Baseline comparison reported: what failed before, what fails now.
- Sibling issues found during tracing are listed, fixed or not.
