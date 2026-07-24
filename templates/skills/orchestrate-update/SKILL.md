---
name: orchestrate-update
description: Refresh the orchestration system ({{CLAUDE_DIR}}/orchestrator-spec/, orchestration.json, agents/, skills/orchestrate/) against the CURRENT Claude Code installation — version, plugins, MCP servers, agent frontmatter support, models. Use when the user says "update orchestrate", "/orchestrate-update", or asks to re-sync the orchestration system with the latest Claude Code state. Not for running orchestrated tasks — that's /orchestrate.
---

# Orchestrate Update

Maintenance skill for the orchestration system built in
`{{CLAUDE_DIR}}/orchestrator-spec/`. Re-inspects the live installation and
reconciles spec + runtime files. Read-only discovery, then targeted edits
only where drift is found — never a blind full regenerate.

## Procedure

### 1. Re-inspect the installation (live, read-only)

- `claude --version`.
- `{{CLAUDE_DIR}}/settings.json` → `enabledPlugins` (true/false per plugin).
- Session's available-skills listing and available-agent-types listing
  (system context) — the authoritative current native/user/project/plugin
  skill and agent inventory.
- `{{CLAUDE_DIR}}/.claude.json` and `{{CLAUDE_DIR}}/.mcp.json` → configured MCP
  servers; compare against the session's actual `mcp__<server>__*` tool
  listing to find newly connected or newly failed servers.
- `{{CLAUDE_DIR}}/agents/`, `{{CLAUDE_DIR}}/plugins/marketplaces/**/agents/*.md` →
  sample 2-3 shipped agent frontmatter blocks to re-verify which fields
  are supported (name/description/model/effort/color/tools/
  disallowedTools/initialPrompt/Agent(...) restriction syntax observed
  previously). Note any field that appears that wasn't in
  generation-plan.md's supported list, or a previously-assumed field that
  now appears unsupported.
- Known model IDs available to this user (from system context /
  CLAUDE.md): confirm `opus`/`sonnet`/`haiku` still map to the intended
  tiers for orchestrator/judge/others; flag if a materially better default
  now exists (e.g. a new Opus/Sonnet point release) without changing
  models unprompted.

### 2. Diff against the spec's recorded state

Compare live findings to what's currently written in:
- `orchestrator-spec/README.md` (environment notes, date/version)
- `orchestrator-spec/generation-plan.md` (version-support notes)
- `orchestrator-spec/discovery/plugin-discovery.md` and `mcp-discovery.md`
  (known-disabled / known-failed lists)
- `orchestration.json` + `orchestration.template.json`
  (`capabilities.explicitDeny`)
- `README-orchestration.md` §13 (Excluded capabilities) and §14
  (Unsupported/not used features)
- Agent frontmatter in `{{CLAUDE_DIR}}/agents/*.md` (`tools:` allowlists —
  newly available relevant MCP tools or plugin skills worth adding;
  newly-disabled ones to remove)

Build a short change list: additions, removals, now-supported features to
adopt, now-unsupported assumptions to correct. Nothing else — don't
rewrite content that hasn't drifted.

### 3. Apply targeted edits

- Update `capabilities.explicitDeny` in BOTH `orchestration.json` and
  `orchestrator-spec/orchestration.template.json` to the current
  failed/disabled set (add newly-failed, remove newly-fixed).
- Update the "Excluded capabilities" and version/date lines in
  `README-orchestration.md` and `orchestrator-spec/README.md`.
- If a previously-unsupported frontmatter field is now confirmed
  supported (or vice versa), update `generation-plan.md`'s version-support
  notes AND the relevant agent file(s) in `{{CLAUDE_DIR}}/agents/` — but only
  add a field if it demonstrably improves enforcement (e.g. a real
  `permissionMode` or `maxTurns` key appearing in shipped agents); don't
  speculatively add fields.
- Add newly-relevant read-only MCP tools or skills to a delegate's `tools:`
  allowlist ONLY when they fit that role's existing permission envelope
  (read-only agents never gain mutating tools). Remove tools for
  since-removed/disabled servers or plugins.
- Never touch: workflow limits (max 4 parallel, max 2 correction cycles),
  permission policy (balanced, no bypassPermissions), model assignments,
  memory settings, `defaultGlobalAgent: false` — these are user decisions,
  not discovery outputs. If the installation seems to demand a change here
  (e.g. a role's model was removed from the account), stop and ask instead
  of changing it silently.

### 4. Validate

Re-run the same checks used at initial install:
- Both JSON files parse and still satisfy: `maximumParallelWorkers==4`,
  `maximumCorrectionCycles==2`, `allowBypassPermissions==false`,
  `allowDestructiveGit==false`, `persistentAgentMemory==false`,
  `allowRepositoryMemoryWrites==false`, `defaultGlobalAgent==false`.
- Every agent file: valid YAML frontmatter, correct name/model/effort,
  only task-orchestrator has no tool restriction (full toolset), no
  `Agent` tool on any delegate, no Edit/Write on codebase-researcher or
  result-judge, no bypassPermissions anywhere, all six mandatory rule
  blocks still present verbatim.
- Skill files (`orchestrate`, `orchestrate-update`) still have valid
  frontmatter and are registered (check the live skill listing).
- No credentials introduced anywhere.

### 5. Report

Short summary only — no full file dumps: what changed (version, plugins
added/removed/enabled/disabled, MCP servers added/failed, frontmatter
fields reconciled, tool allowlist deltas), what was checked and found
unchanged, what needs the user's explicit decision (if anything), and
validation pass/fail.

## Notes

- This skill mutates global config (`{{CLAUDE_DIR}}/agents/`,
  `{{CLAUDE_DIR}}/orchestration.json`, `{{CLAUDE_DIR}}/orchestrator-spec/`,
  `{{CLAUDE_DIR}}/skills/`). Treat it like the destructive-adjacent maintenance
  it is: read before overwrite, edit narrowly, never blanket-regenerate
  files that haven't drifted.
- Does not touch `{{CLAUDE_DIR}}/settings.json`, enable/disable plugins, or
  install/update/repair any MCP server or plugin — discovery only, never
  remediation of third-party capabilities (same boundary as the original
  install).
- If nothing has drifted, say so plainly and make no edits.
