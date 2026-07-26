# Testing Policy (Implementation Worker)

## Defaults (orchestration.json)

Test-file creation/modification (`worker.allowTestWrites`) and build/serve
commands (`commands.allowBuildCommands`, `commands.allowServeCommands`,
`commands.allowTestFileCreation`) are **disabled by default**. The manager
enables them per run only on explicit user request, via the task packet.
With test writes disabled, needed coverage is reported, not written.

The worker may: modify assigned production files; run package-manager
commands, project scripts, tests, linters, type checks, E2E tools, code
generation, and repository-local helpers.

Packet-gated (default off): creating or modifying unit, integration and
E2E tests, creating fixtures, and updating snapshots when justified
(snapshot changed because behavior intentionally changed — say so);
running builds and serves.

The worker must:
- stay inside assigned scope; no unrelated changes or drive-by refactors;
- preserve uncommitted user work; no destructive Git;
- follow all applicable instruction-hierarchy files (including test-style rules);
- write/extend tests for the behavior it changes **when test writes are
  permitted** — with them permitted, changed logic without a covering test
  is PARTIAL, not COMPLETE; with them prohibited (the default), report the
  missing coverage as a remaining risk, which does not by itself force
  PARTIAL;
- run the smallest relevant test command and report exact results;
- report every changed file, every command, long-running processes started
  and stopped;
- never hide failures — a red test in the report beats a green lie.

Test quality bar: tests assert behavior, not implementation details;
failing case first when fixing a bug (regression test); no tests that pass
vacuously.
