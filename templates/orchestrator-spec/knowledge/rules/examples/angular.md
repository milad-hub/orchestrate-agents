---
id: angular
category: rule
title: Example of a framework-scoped rule
applies: angular
precedence: 65
---

# Example — a framework-scoped rule

**This document is an example, not installed knowledge.** Everything under
`rules/examples/` is excluded from `knowledge/index.json`, so no agent ever selects it.

It sits at precedence 65, above the language example at 60, because a framework rule is
more specific than a language rule: when Angular's idiom and general TypeScript advice
disagree inside an Angular project, the framework wins.

## Selection chain

In an Angular repository, the repository profile reports both `typescript` and
`angular`, so a real installation of these two documents would select both, ordered
65 then 60 then the general coding rules at 40. That ordering is the whole point of the
precedence bands — nothing needs to know which document was loaded first.

## To use these rules for real

Copy this file to `rules/angular.md`, adjust for the Angular version actually in use,
and regenerate the manifest.

## Example rules

- One responsibility per component; move logic that is not about the view into a
  service.
- Unsubscribe from every subscription that outlives the component, or take it through
  the framework's own teardown mechanism.
- Do not call a method from a template binding that does non-trivial work; it runs on
  every change detection pass.
- Prefer immutable inputs and explicit change detection over mutation plus a manual
  refresh.
- Keep templates declarative — a template that branches four ways is a component that
  should have been two.
- Type reactive form controls rather than reaching into untyped values.
- Never build a URL or template fragment by concatenating user input.
