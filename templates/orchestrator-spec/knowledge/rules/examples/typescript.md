---
id: typescript
category: rule
title: Example of a language-scoped rule
applies: typescript, javascript
precedence: 60
---

# Example — a language-scoped rule

**This document is an example, not installed knowledge.** Everything under
`rules/examples/` is excluded from `knowledge/index.json`, so no agent ever selects it.
It exists to show what a technology-scoped rule looks like, because the shape is easier
to copy than to describe.

Language rules are not shipped as installed knowledge on purpose: this bundle is
installed once for every repository on the machine, and asserting TypeScript rules in a
repository that has no TypeScript is how a knowledge layer starts producing confident
irrelevant advice. Framework rules belong to the repository that has the framework.

## What makes it technology-scoped

Two fields:

- `applies: typescript, javascript` — the tokens are matched against the repository
  profile. In a repository with neither, this document is never selected.
- `precedence: 60` — the technology band, above the general coding rules at 40. More
  specific guidance outranks less specific guidance.

## To use these rules for real

Copy this file to `rules/typescript.md`, keep or adjust the content, and regenerate the
manifest. From then on it is selected in TypeScript repositories and ignored elsewhere.

## Example rules

- Prefer explicit types at module boundaries; let inference do the work inside a
  function body.
- Do not use `any` to escape a type error. It moves the error to run time and to
  someone else.
- Do not assert away a null with `!` where the value can genuinely be null; handle it.
- Narrow with type guards rather than casting.
- `unknown` over `any` for values whose shape is not yet established.
- Discriminated unions over optional-field combinations that encode a state machine.
- `readonly` for anything that is not intended to be mutated after construction.
- Do not export a type only used in one file.
