# Skills

**Spec:** [knowledge/skills/](../templates/orchestrator-spec/knowledge/skills/),
[knowledge/templates/skill.md](../templates/orchestrator-spec/knowledge/templates/skill.md),
[agents/task-orchestrator.spec.md](../templates/orchestrator-spec/agents/task-orchestrator.spec.md)

Nine skills ship: `feature-development`, `bug-fixing`, `debugging`,
`code-review`, `testing`, `refactoring`, `documentation`, `performance`,
`security`.

## What makes a skill different from prose

Two things:

- It is **named**, so a packet points at it instead of carrying it.
- It states its own **completion criteria**, so finishing is a check rather
  than an opinion.

Without the second, a skill is a paragraph with a filing system. The completion
criteria are what the delegate reports against and what the manager checks.

## The eight sections

Purpose, prerequisites, required context, execution steps, expected outputs,
validation checklist, quality checklist, completion criteria. All eight are
mandatory — `verify-install.py` fails a descriptor missing one.

Two of them carry more weight than they look:

**Purpose says when the skill is the wrong choice.** A skill that never says
this gets used everywhere, and the cost lands on whoever reads the resulting
report.

**Validation and quality are separate on purpose.** Validation is mechanical —
commands, exit codes, diff inspection. Quality is judgement. Merging them makes
the mechanical half unmechanical, and a checklist that requires judgement is one
nobody can fail.

## Why debugging and bug-fixing are separate

`debugging` ends at an identified cause. `bug-fixing` starts there.

Conflating them loses the reviewable boundary between finding and changing —
which is where the expensive mistake lives, because a fix aimed at the nearest
visible symptom looks exactly like a fix aimed at the cause until a sibling call
site breaks.

## Invocation

The manager selects by name from the manifest, resolves the skill's declared
Required context into the packet, carries its validation checklist and
completion criteria **verbatim**, and checks its prerequisites before dispatch.

Verbatim matters: paraphrasing a criterion turns a check back into an opinion,
which is the thing the criterion existed to prevent.

Trivial work skips skill selection entirely. A skill invoked to look thorough
costs a round trip and buys nothing.

## When to write one

When the procedure recurs. A skill used once is a paragraph that has been given
a filing system.

Copy `knowledge/templates/skill.md`, keep all eight headings, regenerate the
manifest. No core file changes — see [extending.md](extending.md).
