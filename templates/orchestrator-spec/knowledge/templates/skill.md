---
id: skill
category: template
title: Skill descriptor skeleton
applies: *
precedence: 30
---

# Skill descriptor

A skill is a procedure an agent invokes by name instead of the manager
re-explaining it in every packet. Copy the block below into
`knowledge/skills/<id>.md`, keep all eight headings, and regenerate the
manifest.

Two things separate a skill from prose: it is **named**, so a packet can point
at it instead of carrying it, and it **states its own completion criteria**, so
finishing is a check rather than an opinion.

Write one only when the procedure recurs. A skill used once is a paragraph that
has been given a filing system.

---

```
---
id: <kebab-case, matching the filename>
category: skill
title: <one line>
applies: <* or comma-separated technology tokens>
precedence: <0-100>
---
```

## Purpose

What this accomplishes, and — the half people skip — when it is the wrong
choice. A skill that never says when not to use it gets used everywhere.

## Prerequisites

What must be true before starting: state of the repository, work another skill
must have finished, permissions the task packet has to grant. A prerequisite
that is not met stops the skill; it is never assumed.

## Required context

Which knowledge documents this needs resolved, by id. The manager reads this
when assembling the packet, so a skill that needs the security rules says so
here rather than hoping ranking put them in.

## Execution steps

The ordered procedure. Each step is one action with an observable result.
Steps that can be skipped say under what condition — a step with no exit
condition will be followed in cases nobody intended.

## Expected outputs

What exists when this finishes: files changed, commands run, artifacts
produced, findings reported. Named, so the next agent can check for them.

## Validation checklist

How the output is checked, mechanically. Commands with exit codes, tests, diff
inspection. This is what the delegate runs; "review the change" is not a
validation step.

## Quality checklist

What separates acceptable from good. Judgement lives here — not in the
validation list, where it would make a mechanical check unmechanical.

## Completion criteria

The conditions under which this is done, written so each can be reported as met
or not met. The run report answers this list. "Works correctly" is not a
criterion; "`npm test` exits 0 and the new case fails without the fix" is.
