---
id: project-overview
category: memory
title: What the orchestration bundle is and what it is for
applies: *
precedence: 30
---

# Project overview

This bundle installs a manager/researcher/worker/validator/judge multi-agent
orchestration system into a coding CLI. It is markdown, JSON and TOML — there is no
runtime to start and no package to install.

## What it does

A task arrives through `/orchestrate` or by launching the manager agent directly. The
manager classifies the task, discovers what the current session actually has available,
plans, delegates to at most four parallel lower-level agents, reviews every result
against repository evidence, submits the work to an independent judge, runs a bounded
correction loop, and returns one consolidated answer.

## What it is not

- Not a framework the user writes code against.
- Not a service. Nothing runs between sessions.
- Not a model provider client. Nothing here calls an API.

## Why it is built this way

Delegates are constrained by the harness — tool allowlists, permission policy, worktree
isolation — rather than by their prompts, because a prompt is a request and a permission
is a guarantee. Everything a user can configure exists in more than one file, and
`verify-install.py` is what proves those copies still agree.

## Where things live

`orchestrator-spec/` is the platform-neutral source of truth. Everything under
`agents/` and `skills/` is generated from it for a specific CLI. Changing behavior means
changing the spec first and regenerating, never editing a generated file directly.
