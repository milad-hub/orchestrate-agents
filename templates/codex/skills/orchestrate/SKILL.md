---
name: orchestrate
description: Multi-agent orchestration: manager plans, spawns researcher/worker/validator subagents, independent judge reviews. Use for substantial multi-step tasks via /orchestrate or $orchestrate. Not for trivial single-step requests.
---

# Orchestrate

Adopt the Task Orchestrator role IN THIS SESSION. Do not spawn a
`task-orchestrator` subagent -- Codex subagents cannot themselves spawn
further subagents, so the manager must be the top-level session, not a
delegate.

## Steps

1. Take the task text passed as arguments. If empty, ask the user what to
   orchestrate.
2. Read `{{CODEX_DIR}}/agents/task-orchestrator.md` and follow its ENTIRE
   body (instruction hierarchy, dynamic discovery, review rules,
   procedure, hard limits) as your own operating protocol for this task --
   you are the manager. Read `{{CODEX_DIR}}/orchestration.json` as it
   directs, including the default-off flags for test writes and
   build/serve commands.
3. Spawn `codebase-researcher`, `implementation-worker`, and
   `test-validator` as subagents (each gets an automatically isolated git
   worktree -- no flag to set); submit the completed package to
   `result-judge`. Respect `workflow.maximumParallelWorkers` (default 4)
   from orchestration.json, disjoint write scopes, up to 2 judge
   correction cycles, delegation only when useful.
4. Permission questions the workflow raises (destructive Git, external
   mutations, default-off overrides) go to the user directly; delegates
   never self-approve.
5. Finish with the manager's single consolidated report: what was done,
   files changed, validation evidence, judge verdict and resolution,
   correction cycles used, remaining risks, overall status.

## Notes

- If `{{CODEX_DIR}}/agents/task-orchestrator.md` or the 4 delegate
  subagent configs are missing, report that the orchestration system is
  not installed correctly and point to
  `{{CODEX_DIR}}/README-orchestration.md` -- do not improvise a
  substitute.
