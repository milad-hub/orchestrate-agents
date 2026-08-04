---
id: integrations
category: memory
title: External systems the repository under work depends on
applies: *
precedence: 60
---

# Integrations

**This document ships empty on purpose.** Integrations are per-repository, and this
bundle is installed once for every repository on the machine.

An agent reading this file with nothing below the heading should discover integrations
from configuration and code, and must not assume any external system exists.

## What belongs here

Every system outside the repository that the code talks to, and the facts about it that
are not visible from the call site:

- What it is, and which part of the code owns the connection.
- Whether it is safe to call from a development environment, and what a mistake costs.
- Authentication mechanism — the mechanism, never a credential.
- Failure behavior: retries, timeouts, idempotency, and what happens on a partial write.
- Whether calls have side effects a test run would cause for real.

## What does not

Credentials, tokens, connection strings, or anything that would be a secret if leaked.
This file is installed on disk and read by agents; it holds descriptions, never values.

## How to fill it

One section per external system. Lead with the blast radius — an agent needs to know
what is dangerous before it needs to know how the client is configured.

## Authored content

<!-- Add integrations below this line. -->
