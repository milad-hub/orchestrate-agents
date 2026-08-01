---
name: orchestrate-sync
description: Re-sync the orchestration system ({{CLAUDE_DIR}}/orchestrator-spec/, orchestration.json, agents/, skills/) against the current Claude Code install -- version, plugins, MCP servers, frontmatter support, models. Use for "sync orchestrate", "update orchestrate", or /orchestrate-sync. Not for running tasks (that's /orchestrate).
---

# Orchestrate Sync

Maintenance skill for the orchestration system in
`{{CLAUDE_DIR}}/orchestrator-spec/`. Read-only discovery, then targeted edits
only where drift is found -- never a blind full regenerate.

`PY` below means the first of `python3`, `python`, `py -3` that runs. On
Windows `python3` is frequently absent; do not conclude Python is missing
until all three have failed.

## Procedure

### 0. Fast path

Most runs find nothing. Establish that cheaply before spending anything, and
let the verifier do the ordering -- it migrates before it checks, and records
the prompt hashes before anything can edit them.

1. Run, with the version string `claude --version` prints:
   `PY {{CLAUDE_DIR}}/orchestrator-spec/verify-install.py --sync-start {{CLAUDE_DIR}} --cli-version "<version>"`
   It migrates an older config, records the prompt-body hashes if this is the
   first run, verifies the install, and prints one `NEXT:` line.
2. Obey that line. `NEXT: FAST-PATH` means nothing can have moved: skip to
   step 4, report no drift, stop. `NEXT: STOP` means fix what it listed
   before doing anything else -- never by editing a prompt body to make a
   check pass. Only `NEXT: FULL-PASS` continues into steps 1-3.
3. If none of `python3`, `python`, `py -3` runs, do the same work by hand:
   read `install-state.json`, compare `cliVersion`, and treat a missing
   `orchestrator-spec/prompt-hashes.json` as a first run.

Steps 1-3 below are for the case where something actually moved.

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
  did change, prefer the documented frontmatter schema for this release;
  sample 2-3 shipped agent files under `{{CLAUDE_DIR}}/agents/` and
  `{{CLAUDE_DIR}}/plugins/marketplaces/**/agents/*.md` only to corroborate it.
  Another tool's agent file is evidence of what that tool wrote, not of what
  the platform supports.
- Model tiers actually available to this user (from system context /
  CLAUDE.md): which of `opus`/`sonnet`/`haiku` exist, and whether a
  materially better option has appeared.

### 2. Diff against the spec's recorded state

Compare live findings to what is currently written in:
- `orchestrator-spec/install-state.json` (platform, bundle version, last
  seen CLI version and check date)
- `orchestrator-spec/generation-plan.md` (version-support notes)
- `orchestrator-spec/discovery/plugin-discovery.md` and `mcp-discovery.md`
  (known-disabled / known-failed lists)
- `orchestration.json` (`capabilities.explicitDeny`)
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

- Update `capabilities.explicitDeny` in `orchestration.json` to the current
  failed/disabled set (add newly-failed, remove newly-fixed).
  `orchestrator-spec/orchestration.template.json` is the installer's build
  input, not live config -- leave it alone.
- Update the excluded-capabilities and version/date lines in
  `README-orchestration.md`. Leave `install-state.json` alone -- step 4
  writes it, and only if the install verifies.
- If a previously-unsupported frontmatter field is now confirmed supported
  (or vice versa), update `generation-plan.md`'s version-support notes AND
  the relevant agent file(s) -- but only add a field if it demonstrably
  improves enforcement (a real `permissionMode` or `maxTurns` key appearing
  in the documented schema); don't speculatively add fields.
- **Removing** a tool from a delegate's `tools:` allowlist -- because its
  server or plugin is gone or disabled -- is automatic: it only ever narrows
  what a delegate can reach. **Adding** one is not. List proposed additions
  in the report with the role and the reason, and apply them only after the
  user agrees, even when the tool is read-only and fits the role's envelope.
- Never add `Edit`/`Write` to test-validator: they are installed only when
  the user enabled test writes, and the harness withholding them is what
  enforces the read-only default. Same for adding `Agent` to any delegate.
- Never edit a delegate's prompt body. Step 4 hashes it. Frontmatter
  (`tools:`, `model:`, `effort:`) is yours; the prose is not. A deliberate
  prompt change is a re-bless, not a silent edit.
- Model and effort: **verify, don't interrogate.** Step 4's verifier already
  proves that the agent frontmatter, `orchestration.json` and the README
  configuration table agree. Raise the question with the user only when:
  the verifier reports a disagreement; a role's pinned model no longer
  exists on this account; a materially better tier has appeared; or the user
  asked for it (`/orchestrate-sync models`). Otherwise state the current
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
  if these disagree, so never leave them half-done.
- Never touch: workflow limits (max 4 parallel, max 2 correction cycles),
  permission policy (balanced, no bypassPermissions), memory settings,
  `defaultGlobalAgent: false` -- these are user decisions, not discovery
  outputs. If the installation seems to demand a change here, stop and ask
  instead of changing it silently.

### 4. Validate

1. Run `PY {{CLAUDE_DIR}}/orchestrator-spec/verify-install.py --sync-finish
   {{CLAUDE_DIR}} --cli-version "<version>"`. It re-runs every check and,
   only if they all pass, records `cliVersion` and `lastCheckedAt` for you --
   so a run that ends broken cannot leave a state file claiming it succeeded.
   Fix what it names and re-run until it prints `NEXT: DONE`.
2. What it checks is in `verify-install.py`: JSON policy invariants, the
   fanned-out permission flags agreeing, delegate tool allowlists, three-way
   model/effort agreement, each role's mandatory prompt blocks, the blessed
   prompt-body hashes, leftover installer tokens and credential-shaped
   strings -- across this bundle's own files only. That file is the list; a
   prose copy here is what goes stale. Without Python, work through it by
   reading that file.
3. Confirm the `orchestrate` and `orchestrate-sync` skills still appear in
   this session's skill listing with valid frontmatter. The verifier reads
   files; only the session can see the live registry.

### 5. Report

Short summary only -- no file dumps: what changed (version, plugins, MCP
servers, frontmatter fields, tool allowlist deltas), any tool additions
awaiting the user's approval, the current model/effort assignment in one
line, what was checked and found unchanged, what needs the user's explicit
decision, and the verifier's result.

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
