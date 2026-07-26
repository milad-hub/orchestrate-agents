# Generation Plan

How to reconcile runtime artifacts with this spec and their existing
platform templates.

## Inputs

- All files in `{{AGENT_HOME_DIR}}/orchestrator-spec/`
- Existing runtime agent templates, which own platform syntax and compact
  role-specific output schemas.
- Live session inspection: Claude Code version, connected MCP servers,
  enabled plugins, failed/disabled capabilities.

## Outputs

1. `{{AGENT_HOME_DIR}}/orchestration.json` — copy `orchestration.template.json`,
   then set `capabilities.explicitDeny` to the currently failed/disabled
   capability names discovered live. Never bake full capability lists in;
   dynamic discovery stays on.
2. `{{AGENT_HOME_DIR}}/agents/*` — update each existing platform template
   from its role spec. Preserve its platform syntax and runtime-owned
   Required output section. Frontmatter uses only fields verified supported
   on the installed version: `name`, `description`, `model`, `effort`,
   `tools`, `disallowedTools`.
3. `{{AGENT_HOME_DIR}}/skills/orchestrate/SKILL.md` — from `skill/orchestrate.spec.md`.
4. `{{AGENT_HOME_DIR}}/README-orchestration.md` — user documentation.

## Mandatory rules to embed

- ALL agents: the instruction-hierarchy rule (instructions/instruction-governance.md §Mandatory rule).
- Manager: task-scaled discovery and direct-review gates
  (agents/task-orchestrator.spec.md).
- Lower-level agents: capability-packet rule (policies/capability-routing.md §Delegate rule).
- Judge: independent-verification rule (agents/result-judge.spec.md).

## Validation checklist

- JSON parses (`python -m json.tool`).
- Runtime and template JSON contain a non-negative `maximumAgentRetries`,
  a positive `waitSliceSeconds`, and positive `agentTimeoutSeconds` values
  for every role.
- Every agent file has valid YAML frontmatter with a known agent name and
  correct model (opus/haiku/sonnet/haiku/sonnet) and effort.
- task-orchestrator omits `tools:` entirely (it inherits the full set,
  including Agent); every delegate declares a `tools:` allowlist without
  Agent.
- test-validator's allowlist contains `Edit`/`Write` only when test writes
  were enabled at install time.
- Researcher and judge have no Edit/Write/NotebookEdit.
- When enabled, validator Edit/Write remains limited to tests by its body.
- No `permissionMode: bypassPermissions` anywhere.
- Skill does not duplicate the manager prompt; it delegates.
- No credentials in any generated file.
- Orchestrator is not made the default agent (no settings.json change).

## Version-support notes

`/orchestrate-update` rewrites this section with what it verified against
the installed Claude Code version. Until it has run, emit only the
conservative set:

- Agent frontmatter: `name`, `description`, `model`, `effort`, `color`,
  `tools` (including the `Agent(...)` restriction syntax inside `tools:`).
- `disallowedTools` is documented but unused here — the generated agents
  use `tools:` allowlists exclusively.
- Do NOT emit maxTurns, memory, mcpServers, skills, isolation, background,
  or permissionMode as frontmatter keys → enforce those behaviors at
  prompt level and via the Agent tool's `isolation` parameter at spawn
  time.
- Worktree isolation: Agent tool spawn parameter `isolation: "worktree"`;
  the manager passes it when spawning workers.
