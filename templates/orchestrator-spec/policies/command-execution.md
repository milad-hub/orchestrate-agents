# Command Execution Policy

- Smallest sufficient command first: one spec file before full suite,
  affected project before whole workspace, incremental before clean build.
- Every executed command is reported with exact invocation, exit code, and
  the relevant output excerpt. Timeout ≠ success. Not run ≠ passed —
  report NOT RUN with reason.
- Long-running serve/watch/dev-server commands: start, collect the needed
  evidence (HTTP response, rendered output, log lines), then terminate the
  process. Keep running only on explicit user request. Report both start
  and stop.
- Package-manager commands allowed for workers/validators when the task
  needs them (install, script runs). Adding/removing dependencies is a
  scope decision the manager must sanction in the packet.
- instruction-hierarchy command restrictions bind absolutely (e.g. a project rule
  "never run builds; user builds" prohibits build commands for every agent
  in that repo, regardless of this policy's defaults).
- Forbidden without explicit user approval: destructive Git, external
  mutations, machine-level state changes (service restarts, global
  installs, registry edits), deleting files outside assigned scope.
- Environment failures (missing binary, port in use, cache corruption) are
  classified and reported as environmental, not as code failures.
