# MCP Discovery

Sources:
1. Session tool listing — connected servers expose tools named
   `mcp__<server>__<tool>` (deferred tools count; load schemas via
   ToolSearch when needed).
2. Config files (`{{AGENT_HOME_DIR}}/.claude.json`, `{{AGENT_HOME_DIR}}/.mcp.json`, project
   `.mcp.json`) — read-only, to detect *configured but not connected*
   servers, which are FAILED and go to PROHIBITED. Never read or expose
   credentials, tokens, or private endpoints from these files.

Classify each MCP tool read-only vs mutating from its name and description
(e.g. `repo_get_*`, `search_*`, `ctx_read` = read-only;
`repo_create_pull_request`, `wit_update_work_item`, `wiki_create_or_update_page`
= mutating/external). When unsure, treat as mutating.

Role policy:
- Researcher/Judge: read-only MCP tools only.
- Worker/Validator: read-only MCP freely; mutating MCP tools that touch
  external systems (Azure DevOps writes, etc.) require explicit user
  approval routed through the manager (policies/external-systems.md).
- Repository-memory (codebase-memory*): reads allowed for all roles;
  writes (ingest_traces, manage_adr, delete_project) forbidden;
  index_repository/index_status permitted as read-side maintenance of the
  memory index only when a role needs graph queries and the index is stale.

Nothing is known-failed at ship time — this bundle makes no assumption
about which MCP servers are connected on the target machine. Discovery
each run (and `/orchestrate-sync` once after install) finds whatever is
actually configured-but-not-connected and adds it to
`capabilities.explicitDeny`. Do not attempt to repair a failed server.
