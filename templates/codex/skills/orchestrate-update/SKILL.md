---
name: orchestrate-update
description: Re-sync orchestrate multi-agent system against current Codex CLI install -- version, MCP servers, subagent config, deny-list. Use for "update orchestrate" or /orchestrate-update. Not for running tasks (that's /orchestrate).
---

# Orchestrate Update

Maintenance skill for the orchestrate system in
`{{CODEX_DIR}}/orchestrator-spec/`. Read-only discovery, then targeted
edits only where drift is found -- never a blind full regenerate. Full
procedure: `references/orchestrate-update-body.md` -- read it in full
before acting.
