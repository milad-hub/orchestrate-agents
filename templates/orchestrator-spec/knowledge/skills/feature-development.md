---
id: feature-development
category: skill
title: Add behavior that does not exist yet
applies: *
precedence: 40
---

# Feature development

## Purpose

Add new behavior to a repository: understand where it belongs, build the
smallest thing that satisfies the acceptance criteria, and leave it checkable.

Wrong choice when the behavior already exists and is broken — that is
`bug-fixing`, which starts from a symptom rather than from a requirement. Also
wrong when the change is a pure restructuring with no behavior change; that is
`refactoring`.

## Prerequisites

- Acceptance criteria exist and are measurable. Without them there is nothing
  to finish against, and the orchestration workflow does not dispatch work in
  that state.
- The file scope is assigned and disjoint from any concurrent worker's.
- Where tests are expected, the packet has granted test writes; otherwise the
  feature ships with its verification described rather than committed.

## Required context

`conventions`, `coding`, `architecture` (rules), `testing`, and `security` when
the feature touches a trust boundary. `project-overview` and the repository's
own `domain` and `business-rules` when either is populated.

## Execution steps

1. Read the acceptance criteria and restate what done means in one sentence. A
   restatement that is hard to write means the criteria are not yet criteria.
2. Locate where the behavior belongs: the existing module that owns the
   concern, not a new one. Check for an existing helper, utility or pattern
   that already does part of this — reimplementing what lives a few files over
   is the most common form of waste.
3. Trace the affected path end to end before editing, including every caller of
   anything shared you are about to touch.
4. Implement inside the assigned scope. Match the surrounding code's naming,
   layout and idiom.
5. Add or extend tests when test writes are permitted; otherwise state exactly
   what should be tested and why it was not.
6. Run the project's own build, test and lint commands for the affected area.
7. Re-read the diff as a reviewer would, before reporting.

## Expected outputs

- The change, confined to the assigned file scope.
- Test additions, or a stated reason there are none.
- Command output for everything that was run.
- A note of anything discovered but deliberately left alone.

## Validation checklist

- The project's test command exits 0, and its output is reported verbatim.
- Lint and type-check exit 0 for the touched files.
- The new behavior is exercised by something that fails without the change.
- The diff contains no file outside the assigned scope.
- No debugging leftovers: no stray logging, no commented-out code, no TODO.

## Quality checklist

- Would a reviewer who has not read the ticket understand why each hunk exists?
- Is this the smallest change that satisfies the criteria, or does it carry
  speculative structure for a second case nobody has asked for?
- Does it follow the repository's conventions rather than the author's?
- Are errors handled where they occur rather than swallowed?
- Is anything now duplicated that was not before?

## Completion criteria

- Every acceptance criterion is reported as met, each with the evidence that
  shows it.
- Validation checklist fully passed, with command output.
- Scope respected: the diff touches only assigned files.
- Anything not done is named, with the reason.
