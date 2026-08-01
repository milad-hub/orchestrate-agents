# Orchestrator Specification (Source of Truth)

This directory and the runtime templates are **both maintained sources**,
and will be until a deterministic generator exists:

- These specs define shared behavior and policy — role duties, permission
  envelopes, instruction governance, validation and judging rules.
- The runtime templates under `{{AGENT_HOME_DIR}}/agents/` and
  `{{AGENT_HOME_DIR}}/skills/orchestrate/` own platform syntax (Claude
  frontmatter vs Codex TOML) and the compact per-role output schemas.

`generation-plan.md` reconciles the two; it takes the existing runtime
templates as an input, not just this directory. A change to shared
behavior belongs here first, then in both platform templates. Do not
describe the runtime files as generated from these specs alone.

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
| `skill/orchestrate-sync.spec.md` | `/orchestrate-sync` maintenance skill spec |
| `verify-install.py` | The install's invariants, as runnable code |
| `config-ui.py` | The browser settings UI |

## Generated runtime files

- `{{AGENT_HOME_DIR}}/orchestration.json` — effective runtime config
- `{{AGENT_HOME_DIR}}/agents/task-orchestrator.md` (opus, high)
- `{{AGENT_HOME_DIR}}/agents/codebase-researcher.md` (haiku, medium, read-only)
- `{{AGENT_HOME_DIR}}/agents/implementation-worker.md` (sonnet, medium, writes)
- `{{AGENT_HOME_DIR}}/agents/test-validator.md` (haiku, medium, test-writes only)
- `{{AGENT_HOME_DIR}}/agents/result-judge.md` (sonnet, high, read-only)
- `{{AGENT_HOME_DIR}}/skills/orchestrate/SKILL.md`
- `{{AGENT_HOME_DIR}}/skills/orchestrate-sync/SKILL.md`
- `{{AGENT_HOME_DIR}}/README-orchestration.md`

## Regeneration

Ask your assistant: "Regenerate the orchestration runtime files from
{{AGENT_HOME_DIR}}/orchestrator-spec/ following generation-plan.md."
Validation steps are in `generation-plan.md`.

## Keeping it current

Run `/orchestrate-sync` to re-sync this spec and the runtime files
against the live CLI installation (version, plugins, MCP servers, agent
config-field support). This directory ships to both Claude Code and Codex
CLI, so nothing here is specific to either. It edits narrowly — only what's
actually drifted — and never touches workflow limits or permission policy
without asking.

`orchestrator-spec/verify-install.py` is the executable definition of this
install's invariants; `install-state.json` records the platform, bundle
version and last-checked CLI version that `/orchestrate-sync` reads. It
also carries the schema migration (`--migrate`, from schemaVersion 1 or 2)
and the prompt-body blessing (`--bless`) that makes a deliberate prompt
edit distinguishable from tampering.

Upstream: https://github.com/milad-hub/orchestrate-agents

## Environment notes

This bundle ships with no assumptions about your machine — no plugins, MCP
servers, or failed capabilities are baked in. `/orchestrate-sync` writes
what it finds on THIS installation into this section (denied native tools,
failed/disabled capabilities to exclude, verified frontmatter support).
Orchestration never repairs or enables third-party capabilities.
