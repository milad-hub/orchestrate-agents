# Orchestrate Update

Full procedure (Codex CLI). Maintenance skill for the orchestrate system in
`{{CODEX_DIR}}/orchestrator-spec/`. Read-only discovery, then targeted edits
only where drift is found -- never a blind full regenerate.

## Procedure

### 0. Fast path

Most runs find nothing. Establish that cheaply before spending anything.

1. Compare `codex --version` against the version/date line recorded in
   `orchestrator-spec/README.md`.
2. If they match, and the runtime skills listing and the configured MCP
   server roster show nothing that the delegates' `mcp_servers` maps and
   `capabilities.explicitDeny` do not already account for, go straight to
   step 4, report "no drift", and stop.

Steps 1-3 are for the case where something actually moved.

### 1. Re-inspect the installation (live, read-only)

- `~/.codex/config.toml` -> `[mcp_servers.*]` tables: the configured MCP
  server roster. Codex does not expose a live connected-tool listing the way
  some other platforms do -- treat a server as available only if you can
  independently confirm it responds (a successful no-op call), and otherwise
  report "configured" and "actually connected" as two different facts.
- Installed skills: the runtime skills listing (name, description, path)
  under `~/.codex/skills/` and `.codex/skills/`.
- `~/.codex/config.toml` -> `[agents]`: confirm
  `max_concurrent_threads_per_session` is still present and still >=
  `workflow.maximumParallelWorkers` in `orchestration.json`.
- TOML field support -- only when the version changed in step 0. On an
  unchanged version this re-derives a fact that cannot have moved. When it
  did change: sample a few `~/.codex/agents/*.toml` and `.codex/agents/*.toml`
  (including any shipped by other tools on this machine) and note anything
  newly supported or newly unsupported versus what this bundle assumes --
  `name`, `description`, `developer_instructions`, `model`,
  `model_reasoning_effort`, `sandbox_mode`, `mcp_servers`, `skills.config`.
- Model naming for this account: model IDs change often, so treat a stale
  pin as something to raise in step 3, never to rewrite in passing.

### 2. Diff against the spec's recorded state

Compare live findings to what is currently written in:
- `orchestrator-spec/README.md` (environment notes, date/version)
- `orchestrator-spec/generation-plan.md` (version-support notes)
- `orchestration.json` + `orchestrator-spec/orchestration.template.json`
  (`capabilities.explicitDeny`)
- `README-orchestration.md`'s "Excluded capabilities" and "Unsupported / not
  used features" sections -- by name, not by section number; the numbering
  shifts.
- Each delegate's `mcp_servers` map in `{{CODEX_DIR}}/agents/*.toml`

Build a short change list: additions, removals, now-supported features to
adopt, now-unsupported assumptions to correct. Nothing else -- don't rewrite
content that hasn't drifted.

### 3. Apply targeted edits

- Update `capabilities.explicitDeny` in BOTH `orchestration.json` and
  `orchestrator-spec/orchestration.template.json` to the current
  failed/disabled set (add newly-failed, remove newly-fixed).
- Update the excluded-capabilities and version/date lines in
  `README-orchestration.md` and `orchestrator-spec/README.md`.
- If a previously-unsupported TOML field is now confirmed supported (or vice
  versa), update `generation-plan.md`'s version-support notes AND the
  relevant `.toml` file(s) -- but only add a field if it demonstrably
  improves enforcement; don't speculatively add fields.
- Add newly-relevant read-only MCP servers to a delegate's `mcp_servers` map
  ONLY when they fit that role's `sandbox_mode` envelope (`read-only` roles
  never gain a server whose tools plainly mutate state -- inspect its tool
  descriptions, don't infer from its name). Remove servers that are
  since-removed or disabled.
- Never widen a delegate's `sandbox_mode`, and never invent a field that
  would let a subagent spawn further subagents.
- Model and reasoning effort: **verify, don't interrogate.** Step 4's
  verifier already proves that each `.toml`, `orchestration.json` and the
  README configuration table agree. Raise the question with the user only
  when: the verifier reports a disagreement; a pinned model no longer exists
  on this account; a materially better option has appeared; or the user
  asked for it (`/orchestrate-update models`). Otherwise state the current
  assignment in one line of step 5 and change nothing -- a reconciler that
  asks the same question every run is a round-trip that buys nothing.

  When you do ask: show the current value and the shipped rationale below,
  ask once, then write the answer to both the `.toml` files and
  `orchestration.json`'s per-role `desiredEffort` together. Never change
  either silently, and never leave the two disagreeing. If a pinned model no
  longer exists, propose the nearest option rather than quietly downgrading.

  Each delegate ships with its `model` line commented out, inheriting the
  Codex session model, and with `model_reasoning_effort` set to:

  | Role | Effort | Rationale |
  |---|---|---|
  | codebase-researcher | medium | reads and reports; does not author code |
  | implementation-worker | medium | authors production code -- a weak setting here is paid back in correction cycles |
  | test-validator | medium | runs commands and classifies output |
  | result-judge | high | independent review of both the work and the manager |

- Test-file writes and build/serve commands ship OFF and the installer no
  longer asks. Change them **only when the user asks**, and change every
  flag together: `worker.allowTestWrites`, `validator.allowTestWrites`,
  `commands.allowTestFileCreation`,
  `commands.allowBuildCommands`/`allowServeCommands`, and
  `validator.allowBuildCommands`/`allowServeCommands`. The delegates'
  `sandbox_mode` is not the lever here and must not be widened for it.
- Never touch: workflow limits (`maximumParallelWorkers`,
  `maximumCorrectionCycles`), permission policy, memory settings,
  `defaultGlobalAgent: false`, or `~/.codex/config.toml`'s `[agents]` values
  -- these are user decisions, not discovery outputs. If the installation
  seems to demand a change here, stop and ask instead of changing it
  silently.

### 4. Validate

1. Run the shipped verifier:
   `python3 {{CODEX_DIR}}/orchestrator-spec/verify-install.py {{CODEX_DIR}}`
   It checks the JSON policy invariants, that every `.toml` parses with the
   right `sandbox_mode`, three-way effort agreement (`.toml` <->
   `orchestration.json` <-> the README configuration table), each role's
   mandatory prompt blocks, that the manager has no frontmatter and no
   `.toml`, leftover installer tokens and credential-shaped strings. Fix
   what it names and re-run until it exits 0. Do not restate its checks here
   -- that file is the list, and a prose copy is what goes stale.
2. If `python3` is unavailable, work through the same list by hand by
   reading `verify-install.py`.
3. Confirm the `orchestrate` and `orchestrate-update` skills still appear in
   the runtime skills listing with valid frontmatter. The verifier reads
   files; only the runtime can see the live registry.

### 5. Report

Short summary only -- no file dumps: what changed (version, MCP servers, TOML
fields, `mcp_servers` deltas per role), the current model/effort assignment
in one line, what was checked and found unchanged, what needs the user's
explicit decision, and the verifier's result.

## Notes

- This skill mutates `{{CODEX_DIR}}/agents/`,
  `{{CODEX_DIR}}/orchestration.json`, `{{CODEX_DIR}}/orchestrator-spec/`,
  `{{CODEX_DIR}}/skills/`. Treat it like the destructive-adjacent
  maintenance it is: read before overwrite, edit narrowly, never
  blanket-regenerate files that haven't drifted.
- Does not touch `~/.codex/config.toml` beyond confirming the `[agents]`
  table, and does not install/update/repair any MCP server -- discovery
  only, never remediation of third-party capabilities.
- If nothing has drifted, say so plainly and make no edits.
