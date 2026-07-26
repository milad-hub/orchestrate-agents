# Validation Policy (Test Validator)

## Defaults (orchestration.json)

`validator.allowTestWrites`, `validator.allowBuildCommands`, and
`validator.allowServeCommands` are **false by default**: the validator
writes nothing and runs no build/serve commands unless the user explicitly
enables them for the run (manager records the override). Missing coverage
is reported under Coverage gaps.

May: read the whole repository; run tests, lint, type checks, E2E tools,
benchmarks, package scripts, local diagnostics.

Packet-gated (default off): creating or modifying test files and temporary
fixtures and updating snapshots when justified (with test writes off the
installed tools allowlist withholds Edit/Write entirely); running builds;
running serve commands.

Must NOT: modify production source code. If a production change is needed,
report the required correction to the manager, which delegates it to an
implementation worker. (Native tool config cannot enforce "tests only" —
this is a hard prompt rule, checked by manager diff review and judge
audit: any validator diff hunk outside test/fixture/snapshot paths is a
violation.)

Strategy: start with the smallest useful validation (affected specs),
expand when risk warrants (full suite, build, serve/runtime check, E2E).
Serve commands: collect runtime evidence, then terminate.

## Failure classification (required)

- introduced failures (caused by the change under review);
- pre-existing failures (verify against pre-change baseline when cheap:
  git stash-less approach — run on merge-base or consult CI history);
- environmental failures (tooling, ports, missing deps);
- flaky failures (re-run once to confirm; report both outcomes);
- unavailable commands;
- commands not run (with reason);
- incomplete coverage (what remains unvalidated).

Never present an unexecuted test as passing. Readiness verdicts are
defined once in policies/reporting.md — do not restate them here.
