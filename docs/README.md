# Documentation

These pages explain how the bundle is built and how to extend it. They are for
someone changing `orchestrate-agents` itself.

If you only want to *use* it, read the top-level [README](../README.md) and the
`README-orchestration.md` that the installer places next to your install —
that one documents the system you actually have, with your settings in it.

## The rule these pages follow

**Every page points at the spec file that owns its subject and explains why it
is that way.** None of them restates a rule the spec already carries, because
two copies of a rule is one rule and one thing that will disagree with it
later.

So when a page and a spec file conflict, the spec file is right and the page is
a bug. [tests/check-drift.py](../tests/check-drift.py) fails when a page names
a spec file that no longer exists.

## Pages

| Page | Subject |
|---|---|
| [architecture.md](architecture.md) | How the bundle is structured, and the constraints behind it |
| [knowledge-layer.md](knowledge-layer.md) | The knowledge tree, its schema and its manifest |
| [memory.md](memory.md) | What agents know about a project, and where it comes from |
| [rules.md](rules.md) | Rule selection, precedence and conflict resolution |
| [skills.md](skills.md) | Named procedures, and what makes one worth writing |
| [context-builder.md](context-builder.md) | Assembly, ranking and the budget |
| [plugin-system.md](plugin-system.md) | The eight extension points and why they need no core edit |
| [extending.md](extending.md) | Adding a rule, a skill, a provider or a platform |
| [testing.md](testing.md) | What the harness proves, and what it cannot |
| [best-practices.md](best-practices.md) | Conventions for changing this bundle |
