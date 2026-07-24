# Agent Discovery

Sources:
1. Session agent-types listing (authoritative): native agents (Explore,
   Plan, general-purpose, claude, statusline-setup, guide agents), plugin
   agents (`plugin:agent` names), user agents (`{{AGENT_HOME_DIR}}/agents/`),
   project agents (`.claude/agents/`).
2. Agent definition files, for tool/permission inspection before routing
   work to them.

Rules:
- Only the manager spawns agents. It may select native, plugin, user, or
  project agents when they fit a subtask better than the generic
  worker/researcher (e.g. Explore for broad fan-out search, a plugin
  reviewer agent for a diff review) — deliberately, per
  policies/capability-routing.md.
- Before delegating to a third-party agent, read its description and, if
  available, its definition: confirm its toolset matches the intended
  permission envelope (never hand a read-only subtask to an agent with
  Write access when a read-only agent fits).
- Orchestration agents (codebase-researcher, implementation-worker,
  test-validator, result-judge) are the defaults for their roles.
- Project agents may shadow global names; the more specific wins — note
  which was used in the run report.
