---
id: domain
category: memory
title: Domain model and vocabulary of the repository under work
applies: *
precedence: 60
---

# Domain

**This document ships empty on purpose.** A domain model is per-repository, and this
bundle is installed once for every repository on the machine.

An agent reading this file with nothing below the heading should build its picture of
the domain from the repository itself, and must not infer entities or relationships
from this bundle.

## What belongs here

The vocabulary the code assumes you already have:

- Core entities, and what each one actually represents in the business.
- Relationships and cardinalities that are not obvious from the schema.
- Lifecycle and state transitions, including the ones that are one-way.
- Terms whose everyday meaning differs from their meaning in this codebase — the most
  valuable entries, because they are the ones that cause confident wrong changes.

## What does not

A restatement of the database schema, a class diagram, or anything that changes every
time a table does. This file must survive a refactor.

## How to fill it

One section per entity: what it is, what it is not, and where its authoritative
definition lives in the code.

## Authored content

<!-- Add domain description below this line. -->
