---
name: orchestrate
description: Run the multi-agent orchestration workflow (manager → researchers → workers → validator → independent judge) for a substantial task. Use ONLY when the user explicitly invokes /orchestrate <task> or asks for orchestrated multi-agent execution. Not for trivial or single-step requests.
---

# Orchestrate

Adopt the Task Orchestrator role IN THIS SESSION. Do not spawn a
`task-orchestrator` subagent — subagents cannot spawn agents in this
harness, so a delegated manager loses its researcher/worker/validator/
judge pipeline. The main session can spawn agents, so the manager runs
here.

## Steps

1. Take the task text passed as arguments. If empty, ask the user what to
   orchestrate.
2. Read `{{CLAUDE_DIR}}/agents/task-orchestrator.md` and follow its ENTIRE
   body (instruction hierarchy, dynamic discovery, review rules,
   procedure, hard limits) as your own operating protocol for this task —
   you are the manager. Read `{{CLAUDE_DIR}}/orchestration.json` as it
   directs, including the default-off flags for test writes and
   build/serve commands.
3. Delegate via the Agent tool to `codebase-researcher`,
   `implementation-worker` (with `isolation: "worktree"`), and
   `test-validator`; submit the completed package to `result-judge`.
   Respect: ≤4 parallel lower-level agents, disjoint write scopes, ≤2
   judge correction cycles, delegation only when useful.
4. Permission questions the workflow raises (destructive Git, external
   mutations, default-off overrides) go to the user directly; delegates
   never self-approve.
5. Finish with the manager's single consolidated report: what was done,
   files changed, validation evidence, judge verdict and resolution,
   correction cycles used, remaining risks, overall status.

## Notes

- Alternative launch: `claude --agent task-orchestrator` (manager as the
  main session agent — identical behavior). The orchestrator is never
  the default agent.
- If `{{CLAUDE_DIR}}/agents/task-orchestrator.md` or the delegate agent types
  are unavailable, report that the orchestration system is not installed
  correctly and point to {{CLAUDE_DIR}}/README-orchestration.md — do not
  improvise a substitute.
