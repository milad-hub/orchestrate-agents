---
id: proposal
category: template
title: Learning-loop proposal skeleton
applies: *
precedence: 30
---

# Proposal

What an agent writes when a run suggests knowledge worth keeping: a new rule, a
convention, a skill, an architecture improvement, or repository knowledge.

Three rules govern the whole mechanism, and none of them is negotiable:

- **Proposals are never merged automatically.** A human merges them, always.
- **Nothing writes into `knowledge/` or the repository's ADR directory.**
  Proposals go to `.orchestrate/proposals/` and stay there.
- **Gated.** With `knowledge.allowProposals` off — which is how it ships —
  nothing is written at all; a run may mention a suggestion in its report and
  no more.

A proposal without evidence is an opinion with a filename. The evidence
section is what makes it reviewable, and a proposal that cannot fill it should
not be written.

---

```
Proposed: <YYYY-MM-DD>
Run: <what the run was asked to do>
Kind: rule | convention | skill | architecture | repository-knowledge
Target: <the knowledge document this would create or change>
```

## What is proposed

The change, stated as the text that would be added or replaced. Not a
description of a change — the change itself, so a reviewer approves what they
read rather than what they imagine.

## Why

What happened in this run that this would have prevented, made faster, or made
correct. One concrete instance, not a general principle. "This would be good
practice" is what every rejected proposal says.

## Evidence

The specific occurrence: files, commands, output, the decision that was made
and how it was reached. A reviewer must be able to check the claim without
re-running the task.

## Scope

Which repositories this applies to. `*` for anything universally true;
technology tokens where it is not. A proposal claiming universality on the
strength of one repository is the most common way a knowledge tree acquires
confidently wrong global rules.

## Conflicts

Which existing knowledge document this contradicts, narrows, or duplicates —
checked before proposing, not left for the reviewer. "None found" is an
acceptable answer; not looking is not.

## Cost if wrong

What happens if this is accepted and turns out to be a bad rule. A rule that is
cheap to reverse deserves less scrutiny than one that will shape every future
run, and saying which is the proposer's job.
