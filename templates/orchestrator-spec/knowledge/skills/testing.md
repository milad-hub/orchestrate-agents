---
id: testing
category: skill
title: Validate a change against the project's own suite
applies: *
precedence: 45
---

# Testing

## Purpose

Establish whether a change is correct by running the project's own
verification, and classify whatever fails. Used by the validator role.

Wrong choice for writing new behavior's tests as part of building it — that
belongs to `feature-development`. This skill validates; it does not implement.

## Prerequisites

- The change to validate, and knowledge of what it was meant to do.
- The project's canonical commands, discovered from the repository rather than
  invented.
- Test-file writes and build/serve commands are **off** unless the packet
  granted them. Absence of a grant is an answer, not an obstacle.

## Required context

`testing` and `security` rules; `conventions` where the suite has house
patterns.

## Execution steps

1. Identify the project's own build, test and lint commands from its CI,
   scripts and configuration. An invented command that happens to work proves
   nothing about the project.
2. Establish the baseline: what already failed before this change.
3. Run the affected suites. Record every command, its exit code and the
   relevant output.
4. Classify each failure: genuine defect, flake, environment problem, missing
   dependency, or pre-existing.
5. Re-run anything classified as a flake enough times to justify the label.
6. Report unrun commands as NOT RUN. Never infer an outcome from reading code.

## Expected outputs

- Every command with its exit code and output.
- Baseline comparison: failing before, failing now.
- A classification per failure.
- A verdict, with the gaps that qualify it.

## Validation checklist

- Every reported result came from an executed command.
- A timeout is reported as a timeout, never as a pass.
- No suite was filtered or skipped to produce a green result.
- Coverage of the change is stated: which new branches are exercised, which
  are not.
- Production source is untouched — this role never edits it.

## Quality checklist

- Was the right suite run, or merely the fast one?
- Is each classification supported, especially "flake"?
- Are the gaps stated plainly enough that someone would act on them?
- Would this run have caught the failure if it were intermittent?

## Completion criteria

- Verdict issued: PASS, PASS_WITH_GAPS, FAIL, BLOCKED or TIMEOUT.
- Every command reported with exit code and output.
- Failures classified, with the baseline stated.
- Gaps named explicitly rather than implied by silence.
