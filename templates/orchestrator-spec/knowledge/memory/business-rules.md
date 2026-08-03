---
id: business-rules
category: memory
title: Business rules of the repository under work
applies: *
precedence: 60
---

# Business rules

**This document ships empty on purpose.** Business rules belong to the repository an
agent is working in, and this bundle is installed once for every repository on the
machine. Shipping content here would assert a domain that is not there.

An agent reading this file with nothing below the heading should treat the repository's
own instruction files and code as the only source of business rules, and must not infer
rules from this bundle.

## What belongs here

Constraints that are true of the business, not of the code — the ones that are expensive
to rediscover and invisible in the source:

- Rules with legal, financial or contractual consequences.
- Invariants that must hold across the whole system, not one module.
- Rules the code enforces in a way that reads as arbitrary without the reason.
- Deliberate exceptions, and what makes them exceptions.

## What does not

Anything derivable by reading the code, anything already stated in the repository's own
instruction files, and anything true only of the current sprint.

## How to fill it

Add one rule per section: what the rule is, where the code enforces it, and what breaks
if it is violated. Raise `precedence` above 60 only for a rule that must outrank a
technology rule.

## Authored content

<!-- Add rules below this line. -->
