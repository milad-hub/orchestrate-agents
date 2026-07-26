---
name: orchestrate
description: "Multi-agent orchestration: manager plans, spawns researcher/worker/validator subagents, independent judge reviews complex or high-risk work. Use for substantial multi-step tasks via /orchestrate or $orchestrate. Not for trivial single-step requests."
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
3. Spawn only the subagents selected by the manager procedure.
   Implementation workers are isolated automatically; treat other
   subagents as shared unless the runtime says otherwise. Respect the
   configured concurrency, deadline, wait, retry, and correction limits.
4. Permission questions the workflow raises (destructive Git, external
   mutations, default-off overrides) go to the user directly; delegates
   never self-approve.
5. Finish with the manager's single consolidated report: what was done,
   files changed, validation evidence, judge verdict and resolution (or
   the manager compliance-gate result when no judge was warranted),
   correction cycles used, any timed-out delegates and how their scope
   was covered, remaining risks, overall status.

## Notes

- Before adopting the role, run
  `{{CODEX_DIR}}/orchestrator-spec/verify-install.py {{CODEX_DIR}}` with the
  first of `python3`, `python`, `py -3` that runs. If it fails, report what
  it names and ask whether to continue or run `/orchestrate-sync` first --
  a delegate that silently lost a server is cheaper to catch here than three
  steps into a workflow. Skip the check if no Python is available.
- If `{{CODEX_DIR}}/agents/task-orchestrator.md` or the 4 delegate
  subagent configs are missing, report that the orchestration system is
  not installed correctly and point to
  `{{CODEX_DIR}}/README-orchestration.md` -- do not improvise a
  substitute.
