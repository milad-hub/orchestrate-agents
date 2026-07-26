---
name: orchestrate-update
description: Re-sync the orchestration system ({{CLAUDE_DIR}}/orchestrator-spec/, orchestration.json, agents/, skills/) against the current Claude Code install -- version, plugins, MCP servers, frontmatter support, models. Use for "update orchestrate" or /orchestrate-update. Not for running tasks (that's /orchestrate).
---

# Orchestrate Update

Maintenance skill for the orchestration system in
`{{CLAUDE_DIR}}/orchestrator-spec/`. Read-only discovery, then targeted edits
only where drift is found -- never a blind full regenerate.

## Procedure

### 0. Fast path

Most runs find nothing. Establish that cheaply before spending anything.

1. Compare `claude --version` against the version/date line recorded in
   `orchestrator-spec/README.md`.
2. If they match, and this session's own skill listing, agent-type listing
   and `mcp__*` tool listing show nothing that the delegates' `tools:`
   allowlists and `capabilities.explicitDeny` do not already account for,
   go straight to step 4, report "no drift", and stop. Those listings are
   already in context; reading them costs nothing.

Steps 1-3 are for the case where something actually moved.

### 1. Re-inspect the installation (live, read-only)

- `{{CLAUDE_DIR}}/settings.json` -> `enabledPlugins` (true/false per plugin).
- This session's available-skills and available-agent-types listings: the
  authoritative current native/user/project/plugin inventory. Prefer them
  over anything on disk.
- MCP servers: the session's `mcp__<server>__*` tool listing is the ground
  truth for what is actually connected. Consult `{{CLAUDE_DIR}}/.claude.json`
  and `.mcp.json` only to explain a discrepancy, and extract just the
  `mcpServers` keys -- `.claude.json` also holds per-project history and is
  routinely megabytes, so never read it whole.
- Frontmatter field support -- only when the version changed in step 0. On an
  unchanged version this re-derives a fact that cannot have moved. When it
  did change: sample 2-3 shipped agent frontmatter blocks under
  `{{CLAUDE_DIR}}/agents/` and
  `{{CLAUDE_DIR}}/plugins/marketplaces/**/agents/*.md`, and note any field
  that appears which is not in generation-plan.md's supported list, or a
  previously-assumed field that has disappeared.
- Model tiers actually available to this user (from system context /
  CLAUDE.md): which of `opus`/`sonnet`/`haiku` exist, and whether a
  materially better option has appeared.

### 2. Diff against the spec's recorded state

Compare live findings to what is currently written in:
- `orchestrator-spec/README.md` (environment notes, date/version)
- `orchestrator-spec/generation-plan.md` (version-support notes)
- `orchestrator-spec/discovery/plugin-discovery.md` and `mcp-discovery.md`
  (known-disabled / known-failed lists)
- `orchestration.json` + `orchestration.template.json`
  (`capabilities.explicitDeny`)
- `README-orchestration.md`'s "Excluded capabilities" and "Unsupported / not
  used features" sections -- by name, not by section number; the numbering
  shifts.
- Agent frontmatter in `{{CLAUDE_DIR}}/agents/*.md` (`tools:` allowlists --
  newly available relevant MCP tools or plugin skills worth adding;
  newly-disabled ones to remove)

Build a short change list: additions, removals, now-supported features to
adopt, now-unsupported assumptions to correct. Nothing else -- don't rewrite
content that hasn't drifted.

### 3. Apply targeted edits

- Update `capabilities.explicitDeny` in BOTH `orchestration.json` and
  `orchestrator-spec/orchestration.template.json` to the current
  failed/disabled set (add newly-failed, remove newly-fixed).
- Update the excluded-capabilities and version/date lines in
  `README-orchestration.md` and `orchestrator-spec/README.md`.
- If a previously-unsupported frontmatter field is now confirmed supported
  (or vice versa), update `generation-plan.md`'s version-support notes AND
  the relevant agent file(s) -- but only add a field if it demonstrably
  improves enforcement (a real `permissionMode` or `maxTurns` key appearing
  in shipped agents); don't speculatively add fields.
- Add newly-relevant read-only MCP tools or skills to a delegate's `tools:`
  allowlist ONLY when they fit that role's existing permission envelope
  (read-only agents never gain mutating tools). Remove tools for
  since-removed or disabled servers and plugins.
- Never add `Edit`/`Write` to test-validator: they are installed only when
  the user enabled test writes, and the harness withholding them is what
  enforces the read-only default. Same for adding `Agent` to any delegate.
- Model and effort: **verify, don't interrogate.** Step 4's verifier already
  proves that the agent frontmatter, `orchestration.json` and the README
  configuration table agree. Raise the question with the user only when:
  the verifier reports a disagreement; a role's pinned model no longer
  exists on this account; a materially better tier has appeared; or the user
  asked for it (`/orchestrate-update models`). Otherwise state the current
  assignment in one line of step 5 and change nothing -- a reconciler that
  asks the same question every run is a round-trip that buys nothing.

  When you do ask: show the current value and the shipped rationale below,
  ask once, then write the answer to all three locations together. Never
  change a model silently, and never leave the three disagreeing. If a
  role's model no longer exists, propose the nearest tier rather than
  quietly downgrading.

  | Role | Model | Effort | Rationale |
  |---|---|---|---|
  | task-orchestrator | opus | high | accountable for the result; only binds under `claude --agent task-orchestrator` -- `/orchestrate` runs on the session's model |
  | codebase-researcher | haiku | medium | reads and reports; does not author code |
  | implementation-worker | sonnet | medium | authors production code -- a weak model here is paid back in correction cycles |
  | test-validator | haiku | medium | runs commands and classifies output |
  | result-judge | sonnet | high | independent review of both the work and the manager |

- Test-file writes and build/serve commands ship OFF and the installer no
  longer asks. Change them **only when the user asks**, and change them
  everywhere at once: `worker.allowTestWrites`,
  `validator.allowTestWrites`, `commands.allowTestFileCreation`,
  `commands.allowBuildCommands`/`allowServeCommands`,
  `validator.allowBuildCommands`/`allowServeCommands`, and -- for test
  writes -- the `Edit, Write` entries in test-validator's `tools:`
  allowlist, which is what actually enforces it. Step 4's verifier fails
  if the flag and the allowlist disagree, so never leave them half-done.
- Never touch: workflow limits (max 4 parallel, max 2 correction cycles),
  permission policy (balanced, no bypassPermissions), memory settings,
  `defaultGlobalAgent: false` -- these are user decisions, not discovery
  outputs. If the installation seems to demand a change here, stop and ask
  instead of changing it silently.

### 4. Validate

1. Run the shipped verifier:
   `python3 {{CLAUDE_DIR}}/orchestrator-spec/verify-install.py {{CLAUDE_DIR}}`
   It checks the JSON policy invariants, three-way model/effort agreement
   (frontmatter <-> `orchestration.json` <-> the README configuration table),
   delegate tool allowlists, each role's mandatory prompt blocks, leftover
   installer tokens and credential-shaped strings. Fix what it names and
   re-run until it exits 0. Do not restate its checks here -- that file is
   the list, and a prose copy is what goes stale.
2. If `python3` is unavailable, work through the same list by hand by
   reading `verify-install.py`.
3. Confirm the `orchestrate` and `orchestrate-update` skills still appear in
   this session's skill listing with valid frontmatter. The verifier reads
   files; only the session can see the live registry.

### 5. Report

Short summary only -- no file dumps: what changed (version, plugins, MCP
servers, frontmatter fields, tool allowlist deltas), the current model/effort
assignment in one line, what was checked and found unchanged, what needs the
user's explicit decision, and the verifier's result.

## Notes

- This skill mutates global config (`{{CLAUDE_DIR}}/agents/`,
  `{{CLAUDE_DIR}}/orchestration.json`, `{{CLAUDE_DIR}}/orchestrator-spec/`,
  `{{CLAUDE_DIR}}/skills/`). Treat it like the destructive-adjacent
  maintenance it is: read before overwrite, edit narrowly, never
  blanket-regenerate files that haven't drifted.
- Does not touch `{{CLAUDE_DIR}}/settings.json`, enable/disable plugins, or
  install/update/repair any MCP server or plugin -- discovery only, never
  remediation of third-party capabilities (same boundary as the install).
- If nothing has drifted, say so plainly and make no edits.
