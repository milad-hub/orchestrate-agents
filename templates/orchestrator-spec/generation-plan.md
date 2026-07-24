# Generation Plan

How to (re)generate runtime artifacts from this spec.

## Inputs

- All files in `{{AGENT_HOME_DIR}}/orchestrator-spec/`
- Live session inspection: Claude Code version, connected MCP servers,
  enabled plugins, failed/disabled capabilities.

## Outputs

1. `{{AGENT_HOME_DIR}}/orchestration.json` — copy `orchestration.template.json`,
   then set `capabilities.explicitDeny` to the currently failed/disabled
   capability names discovered live. Never bake full capability lists in;
   dynamic discovery stays on.
2. `{{AGENT_HOME_DIR}}/agents/*.md` — one file per spec in `agents/`. Frontmatter
   uses only fields verified supported on the installed version:
   `name`, `description`, `model`, `effort`, `tools`, `disallowedTools`.
   Body embeds the mandatory rules (see below) plus the role spec.
3. `{{AGENT_HOME_DIR}}/skills/orchestrate/SKILL.md` — from `skill/orchestrate.spec.md`.
4. `{{AGENT_HOME_DIR}}/README-orchestration.md` — user documentation.

## Mandatory rules to embed

- ALL agents: the instruction-hierarchy rule (instructions/instruction-governance.md §Mandatory rule).
- Manager: dynamic-discovery rule + manager-review rule (agents/task-orchestrator.spec.md).
- Lower-level agents: capability-packet rule (policies/capability-routing.md §Delegate rule).
- Judge: independent-verification rule (agents/result-judge.spec.md).

## Validation checklist

- JSON parses (`python -m json.tool`).
- Every agent file has valid YAML frontmatter with a known agent name and
  correct model (opus/haiku/haiku/haiku/sonnet) and effort.
- Only task-orchestrator's `tools` includes `Agent(...)`.
- Researcher and judge have no Edit/Write/NotebookEdit.
- Validator has Edit/Write but body forbids production-source writes.
- No `permissionMode: bypassPermissions` anywhere.
- Skill does not duplicate the manager prompt; it delegates.
- No credentials in any generated file.
- Orchestrator is not made the default agent (no settings.json change).

## Version-support notes (Claude Code 2.1.218, re-verified 2026-07-23 via
/orchestrate-update; scanned all 42 shipped plugin agent files)

- Supported agent frontmatter, DIRECTLY OBSERVED in shipped plugin
  agents: name, description, model, effort, color, tools, initialPrompt,
  Agent(...) restriction syntax (inside `tools:`).
- `disallowedTools` is documented by Claude Code but was NOT observed in
  any of the 42 sampled shipped agents (all use `tools:` allowlists
  instead) — treat as unconfirmed on this installation; our generated
  agents use `tools:` allowlists exclusively, so this doesn't block
  anything, but don't cite it as verified-supported.
- NOT verified on this version: maxTurns, memory, mcpServers, skills,
  isolation, background, permissionMode as frontmatter keys → do not emit;
  enforce those behaviors at prompt level and via the Agent tool's
  `isolation` parameter at spawn time.
- Per-agent effort: supported (`effort:` frontmatter).
- Worktree isolation: supported as Agent tool spawn parameter
  `isolation: "worktree"`; manager passes it when spawning workers.
