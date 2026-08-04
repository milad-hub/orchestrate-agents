---
id: code-review
category: skill
title: Review a change against evidence
applies: *
precedence: 45
---

# Code review

## Purpose

Judge a change on what it does, using the repository as evidence rather than
the author's account of it. Used by the manager's own review of delegate
output and by the independent judge.

Wrong choice for reviewing an idea before it exists — that is a design
question, not a review. Wrong as a substitute for running the tests: a review
that assumes the suite passes is reviewing a claim.

## Prerequisites

- The complete diff, not a summary of it.
- The acceptance criteria the change was meant to satisfy.
- Whatever command output the author reported, so it can be checked rather
  than trusted.

## Required context

`coding`, `architecture`, `security`, `testing`, `conventions`, and the
repository's own instruction files — which outrank all of them.

## Execution steps

1. Read the acceptance criteria first, then the diff. Reading in the other
   order makes the diff feel like the requirement.
2. Read every changed hunk, and open the surrounding file for any hunk whose
   correctness depends on context outside it.
3. Check the claims: re-run the commands whose output was reported. A reported
   exit code is a claim until observed.
4. Look for what is absent — the caller that was not updated, the error path
   with no handling, the test that does not exist for the branch that was added.
5. Check scope: does the diff contain anything the task did not ask for?
6. Rank findings by consequence, not by how easy they are to describe.

## Expected outputs

- Findings, each naming file and line, what is wrong, and what would fix it.
- A severity for each, and an explicit statement when there are none.
- Which claims were verified and which could not be.
- A verdict that follows from the findings.

## Validation checklist

- Every finding names a location and a concrete failure, not a preference.
- Every reported command was re-run, or listed as unverified.
- The acceptance criteria are each marked met or not met.
- Instruction-hierarchy compliance checked, including nested instruction files
  covering the touched paths.
- No finding invented to look thorough: no findings is a valid result.

## Quality checklist

- Are the findings ranked so the important one is not third?
- Is each one actionable without a conversation?
- Does the review distinguish a defect from a style preference, and say which?
- Was the change judged against this repository's conventions rather than
  general habit?
- Would this review have caught the problem if it were subtler?

## Completion criteria

- Verdict issued, with findings ranked by severity.
- Every acceptance criterion marked met or not met, with evidence.
- Unverifiable claims listed as unverified rather than accepted.
- Scope violations named, if any.
