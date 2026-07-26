---
name: orchestrate-sync
description: Re-sync orchestrate multi-agent system against current Codex CLI install -- version, MCP servers, subagent config, deny-list. Use for "sync orchestrate", "update orchestrate", or /orchestrate-sync. Not for running tasks (that's /orchestrate).
---

# Orchestrate Sync

Maintenance skill for the orchestrate system in
`{{CODEX_DIR}}/orchestrator-spec/`. Read-only discovery, then targeted
edits only where drift is found -- never a blind full regenerate. Full
procedure: `references/orchestrate-sync-body.md` -- read it in full
before acting.
