---
id: coding
category: rule
title: Coding rules that hold in every repository
applies: *
precedence: 40
---

# Coding rules

Language-neutral by design. Anything that only makes sense for one stack belongs in a
technology-scoped rule with a narrower `applies` — see `rules/examples/`.

## Match the code you are changing

Naming, layout, error handling, comment density and idiom come from the surrounding
file, not from preference. A file with two competing styles costs more than either
style would have.

## Read before you change

Understand what a function does and who calls it before editing it. A change that is
correct locally and wrong for one caller is a regression that looks like a fix.

## Fix causes, not symptoms

A report names a symptom. Before editing, find every caller of what you are about to
touch. One guard in the shared path beats a guard in each caller, and leaves no sibling
still broken.

## Keep the change scoped

Do what was asked. Unrequested refactors, abstractions and dependencies make a change
unreviewable and hide the part that mattered.

## No speculative structure

No interface with one implementation, no factory for one product, no configuration for
a value that never changes. Add the seam when the second case arrives.

## Validate at trust boundaries

Anything crossing a process, user or network boundary is validated where it enters, not
where it is used.

## Errors must survive

Do not swallow an exception, do not discard its cause, and do not report success on a
path that failed. An error that vanishes is worse than one that crashes.

## Do not silence the tooling

Fixing a warning means addressing what it reports. Suppressing it moves the failure to
whoever trusts the clean output.

## Leave the reason, not the narration

Comment why something non-obvious is done, not what the next line does. A comment that
restates the code goes stale and starts lying.
