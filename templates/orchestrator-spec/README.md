# Orchestrator Specification (Source of Truth)

This directory is the maintainable source for the global multi-agent
orchestration system. The files under `{{AGENT_HOME_DIR}}/agents/` and
`{{AGENT_HOME_DIR}}/skills/orchestrate/` plus `{{AGENT_HOME_DIR}}/orchestration.json` are
**generated build artifacts** derived from these specs. Edit here, then
regenerate.

## Layout

| Path | Purpose |
|---|---|
| `architecture.md` | Roles, flow, trust boundaries |
| `orchestration.template.json` | Config template (pre-discovery) |
| `generation-plan.md` | How runtime files are generated/regenerated |
| `discovery/` | Dynamic capability/command/instruction discovery specs |
| `instructions/` | Instruction-hierarchy governance and instruction precedence |
| `policies/` | Permissions, routing, testing, judging, security, etc. |
| `agents/` | Per-agent full specifications |
| `skill/orchestrate.spec.md` | `/orchestrate` entry-point skill spec |

## Generated runtime files

- `{{AGENT_HOME_DIR}}/orchestration.json` — effective runtime config
- `{{AGENT_HOME_DIR}}/agents/task-orchestrator.md` (opus, high)
- `{{AGENT_HOME_DIR}}/agents/codebase-researcher.md` (haiku, medium, read-only)
- `{{AGENT_HOME_DIR}}/agents/implementation-worker.md` (haiku, medium, writes)
- `{{AGENT_HOME_DIR}}/agents/test-validator.md` (haiku, medium, test-writes only)
- `{{AGENT_HOME_DIR}}/agents/result-judge.md` (sonnet, high, read-only)
- `{{AGENT_HOME_DIR}}/skills/orchestrate/SKILL.md`
- `{{AGENT_HOME_DIR}}/README-orchestration.md`

## Regeneration

Ask Claude Code: "Regenerate the orchestration runtime files from
{{AGENT_HOME_DIR}}/orchestrator-spec/ following generation-plan.md." Validation steps
are in `generation-plan.md`.

## Keeping it current

Run `/orchestrate-update` to re-sync this spec and the runtime files
against the live Claude Code installation (version, plugins, MCP servers,
agent frontmatter support). It edits narrowly — only what's actually
drifted — and never touches workflow limits, permission policy, or model
assignments without asking.

## Environment notes (as of 2026-07-23, Claude Code 2.1.218 — last synced via /orchestrate-update)

- Native Read/Grep/Glob are permission-denied globally in this user's
  settings (lean-ctx shadow routing). Agents rely on lean-ctx `ctx_*` MCP
  tools and Bash for inspection.
- Failed/disabled capabilities excluded: `tokensave` (MCP, failing),
  `chrome-devtools-mcp@claude-plugins-official` (plugin, disabled).
- Do not repair/enable third-party capabilities as part of orchestration.
