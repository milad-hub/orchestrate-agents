# Capability Discovery

The manager performs capability discovery at the **beginning of every
orchestration run**. The live session is the source of truth. Never rely on
hardcoded plugin or MCP names; `orchestration.json` only carries deny
entries and policy flags.

Discovery is a *reading* step, not a crawl. The session context already
lists the tools, agent types, skills, and MCP servers currently available,
with their descriptions — read that listing rather than shelling out to
enumerate it, and never open a skill or agent body just to decide whether
to use it. Repository-local commands are the exception: those come from the
repo (see command-discovery.md), scoped to the validation actually planned.

## What is available to discover

- Native Claude Code tools (Bash, Edit, Write, Agent, Skill, ToolSearch,
  WebFetch, WebSearch, TodoWrite, LSP, Monitor, etc. — as exposed in the
  session, including deferred tools surfaced via ToolSearch).
- Native + bundled skills, user skills (`{{AGENT_HOME_DIR}}/skills/`), project skills
  (`.claude/skills/`), plugin skills — from the session's available-skills
  listing.
- Native agents (Explore, Plan, general-purpose, claude, …), user agents
  (`{{AGENT_HOME_DIR}}/agents/`), project agents (`.claude/agents/`), plugin agents —
  from the session's available-agent-types listing.
- Plugin commands and hooks (settings.json + plugin manifests; read-only
  inspection only).
- MCP servers and their tools (session tool listing, `mcp__<server>__<tool>`
  naming). Note failed servers (configured but absent from session).
- Language servers (typescript-lsp plugin / LSP tool).
- CLI helpers (rtk, gh, az, package managers), repository commands, build
  systems, test frameworks, CI configuration, package manager, repository
  structure, Git status.
- Applicable instruction-hierarchy (see instructions/instruction-file-discovery.md).

## Catalog entry fields (record when determinable)

canonical name; display name; type (tool/skill/agent/command/hook/MCP server/
MCP tool/LSP/CLI/repo command); source; scope (global/project/plugin/session);
description; enabled status; read-only vs mutating; required permissions;
tool requirements; suitable roles; suitable task categories; side effects;
context cost; likely latency; trust considerations; fallback.

## Rules

- Inspect a capability's description or instructions before recommending it.
  Never infer behavior from a name alone.
- Do not print the full catalog unless the user asks; keep it internal.
- Failed, disabled, or explicitly denied capabilities go straight to
  PROHIBITED lists (see `capabilities.explicitDeny` in orchestration.json).
- Discovery is read-only: never enable, disable, install, update, repair, or
  reconfigure any capability during discovery.
