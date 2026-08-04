---
id: security
category: skill
title: Review a change for security consequences
applies: *
precedence: 85
---

# Security review

## Purpose

Examine a change for the ways it could be abused, and report what is found —
including when reporting is inconvenient.

Precedence 85: this sits in the security band, so its guidance is never
outranked by convenience, deadline or style. Wrong choice as a substitute for
the `security` rules, which apply to every task whether or not this skill is
invoked.

## Prerequisites

- The complete change, and knowledge of which trust boundaries it is near.
- The repository's own security conventions, where it has them.

## Required context

`security` rules first and always, then `architecture`, `coding`, and the
repository's `integrations` where populated — an external system's blast radius
is the thing least visible from a call site.

## Execution steps

1. Identify the trust boundaries the change touches: user input, network,
   deserialization, file paths, process boundaries, anything crossing a
   privilege level.
2. For each, check that validation happens where data enters, not where it is
   used.
3. Check construction of anything interpreted: queries, commands, paths,
   templates, redirects. User-controlled data must never be concatenated into
   them.
4. Check secrets: none in source, logs, error messages, test fixtures or
   documentation. Report the location and category of anything found — never
   the value.
5. Check what the change makes reachable that was not reachable before,
   including error paths and debug routes.
6. Check permissions and defaults: does anything now default to more access
   than before?
7. Check dependencies added, and what they bring with them.

## Expected outputs

- Findings, each with location, the mechanism of abuse, and the fix.
- Severity per finding, judged by consequence.
- An explicit statement when nothing was found.
- Anything that could not be assessed, named as unassessed.

## Validation checklist

- Every trust boundary the change touches was enumerated and checked.
- No secret value appears anywhere in the report.
- Each finding names a concrete path to abuse, not a general worry.
- Defaults were checked, not just the code that was written.
- Findings outside the task's scope are reported anyway.

## Quality checklist

- Is each finding real, or theatre that will train people to ignore the next
  one?
- Is severity judged by consequence rather than by how easy it was to spot?
- Does the fix close the class of problem, or only the instance?
- Was the absence of a check noticed, not just the presence of a bad one?

## Completion criteria

- Every touched trust boundary enumerated with a verdict.
- Findings reported with severity and a concrete fix, or "none found" stated
  explicitly.
- No credential values echoed anywhere.
- Unassessable areas named rather than passed over in silence.
