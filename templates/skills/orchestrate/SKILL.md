---
name: orchestrate
description: Run the multi-agent orchestration workflow (manager → researchers → workers → validator, plus an independent judge for complex or high-risk work) for a substantial task. Use ONLY when the user explicitly invokes /orchestrate <task> or asks for orchestrated multi-agent execution. Not for trivial or single-step requests.
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
3. Delegate only the roles selected by the manager procedure. Spawn
   `implementation-worker` with `isolation: "worktree"`; respect its
   concurrency, deadline, retry, and correction limits. Delegates notify
   you when they finish — do not poll.
4. Permission questions the workflow raises (destructive Git, external
   mutations, default-off overrides) go to the user directly; delegates
   never self-approve.
5. Finish with the manager's single consolidated report: what was done,
   files changed, validation evidence, judge verdict and resolution (or
   the manager compliance-gate result when no judge was warranted),
   correction cycles used, any timed-out delegates and how their scope
   was covered, remaining risks, overall status.

## Notes

- You run as the manager on THIS session's model. The `model:`/`effort:`
  in `agents/task-orchestrator.md` apply only to the alternative launch
  `claude --agent task-orchestrator` (identical behavior otherwise). The
  orchestrator is never the default agent.
- If `{{CLAUDE_DIR}}/agents/task-orchestrator.md` or the delegate agent types
  are unavailable, report that the orchestration system is not installed
  correctly and point to {{CLAUDE_DIR}}/README-orchestration.md — do not
  improvise a substitute.
