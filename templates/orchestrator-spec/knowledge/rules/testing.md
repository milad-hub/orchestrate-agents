---
id: testing
category: rule
title: Testing and validation rules
applies: *
precedence: 40
---

# Testing rules

These govern how results are validated and reported. The bundle's own permission
defaults sit on top: test-file writes and build/serve commands are off unless the task
packet enables them.

## Use the project's own commands

Discover the canonical build, test and lint commands from the repository — its CI
configuration, scripts and lockfiles — and run those. An invented command that happens
to work proves nothing about the project.

## Run it, or report it as not run

A command that was not executed is reported as NOT RUN. Never infer an outcome from
reading code, and never describe an expected result as an observed one.

## A timeout is not a pass

Neither is a skipped suite, a filtered run that excluded the failing case, or a green
result from a stale build.

## Evidence, always

Report the exact command, its exit code, and the relevant output. A claim of success
without those is not a result.

## Classify failures

Distinguish a genuine defect from a flake, an environment problem, a missing dependency
and a pre-existing failure. "Tests fail" without a classification sends the next agent
to the wrong place.

## Establish the baseline first

Know which tests failed before the change. Blaming a change for a pre-existing failure
wastes a correction cycle; missing a new failure ships a defect.

## Test the behavior, not the implementation

A test that asserts internals breaks on every refactor and passes through real
regressions.

## One runnable check per non-trivial change

A branch, a loop, a parser, a money or security path leaves behind the smallest thing
that fails if the logic breaks. Trivial one-liners do not need one.

## Never weaken a test to make it pass

Deleting an assertion, loosening a comparison or adding a skip converts a failure into
a silent one. If a test is genuinely wrong, say so and explain why.
