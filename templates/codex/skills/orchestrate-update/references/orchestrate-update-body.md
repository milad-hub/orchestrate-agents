# Orchestrate Update -- full procedure (Codex CLI)

Re-inspects the live Codex installation and reconciles spec + runtime
files. Read-only discovery, then targeted edits only where drift is
found -- never a blind full regenerate.

## 1. Re-inspect the installation (live, read-only)

- `codex --version`.
- `~/.codex/config.toml` -> `[mcp_servers.*]` tables: the configured MCP
  server roster. Codex does not expose as direct a "live connected tool
  listing" as some other platforms -- treat a server as available only
  if you can independently confirm it responds (e.g. a successful
  no-op call), otherwise treat "configured" and "actually connected" as
  two different facts and report both.
- Installed skills: the runtime skills listing (name + description +
  path) under `~/.codex/skills/` and `.codex/skills/`.
- Installed subagent configs: `~/.codex/agents/*.toml` and
  `.codex/agents/*.toml` -- sample a few (including any shipped by other
  tools/marketplaces on this machine) to re-verify which TOML fields are
  actually supported (`name`, `description`, `developer_instructions`,
  `model`, `model_reasoning_effort`, `sandbox_mode`, `mcp_servers`,
  `skills.config`, and any new field that's appeared since this bundle
  was generated). Note anything that looks newly supported or newly
  unsupported vs what this bundle assumes.
- `~/.codex/config.toml` -> `[agents]` table: confirm
  `max_concurrent_threads_per_session` is still present and still
  compatible with `workflow.maximumParallelWorkers` in
  `orchestration.json` (>=).
- Known model naming for this account/session: don't assume any specific
  model ID stays valid -- if a delegate's `model` override (if any) looks
  stale, flag it, don't silently change it.

## 2. Diff against the spec's recorded state

Compare live findings to what's currently written in:
- `orchestrator-spec/README.md` (environment notes, date/version)
- `orchestrator-spec/generation-plan.md` (version-support notes)
- `orchestration.json` + `orchestrator-spec/orchestration.template.json`
  (`capabilities.explicitDeny`)
- `README-orchestration.md`'s excluded-capabilities and
  unsupported-features sections
- Each delegate's `mcp_servers` array in
  `{{CODEX_DIR}}/agents/*.toml`

Build a short change list: additions, removals, now-supported features to
adopt, now-unsupported assumptions to correct. Nothing else -- don't
rewrite content that hasn't drifted.

## 3. Apply targeted edits

- Update `capabilities.explicitDeny` in BOTH `orchestration.json` and
  `orchestrator-spec/orchestration.template.json` to the current
  failed/disabled set (add newly-failed, remove newly-fixed).
- Update the excluded-capabilities and version/date lines in
  `README-orchestration.md` and `orchestrator-spec/README.md`.
- If a previously-unsupported TOML field is now confirmed supported (or
  vice versa), update `generation-plan.md`'s version-support notes AND
  the relevant `.toml` file(s) -- but only add a field if it demonstrably
  improves enforcement; don't speculatively add fields.
- Add newly-relevant read-only MCP servers to a delegate's `mcp_servers`
  array ONLY when they fit that role's `sandbox_mode` envelope
  (`read-only` roles never gain a server whose tools plainly mutate
  state -- inspect its tool descriptions, don't infer from its name).
  Remove servers that are since-removed/disabled.
- Never touch: workflow limits (`maximumParallelWorkers`,
  `maximumCorrectionCycles`), permission policy, model assignments,
  memory settings, `defaultGlobalAgent: false`, or
  `~/.codex/config.toml`'s `[agents]` values -- these are user decisions,
  not discovery outputs. If the installation seems to demand a change
  here, stop and ask instead of changing it silently.

## 4. Validate

Re-run the same checks used at initial install:
- Both JSON files parse and still satisfy: `maximumParallelWorkers==4`,
  `maximumCorrectionCycles==2`, `allowBypassPermissions==false`,
  `allowDestructiveGit==false`, `persistentAgentMemory==false`,
  `allowRepositoryMemoryWrites==false`, `defaultGlobalAgent==false`.
- Every `.toml` file parses as valid TOML; `codebase-researcher.toml` and
  `result-judge.toml` have `sandbox_mode = "read-only"`;
  `implementation-worker.toml` and `test-validator.toml` have
  `sandbox_mode = "workspace-write"`; no subagent config was given the
  ability to spawn further subagents (not a real field -- just confirm
  none was invented). `task-orchestrator.md` has no frontmatter and no
  corresponding `.toml` (it is never a registered subagent).
- Skill files (`orchestrate`, `orchestrate-update`) still have valid
  frontmatter and are registered (check the live skills listing).
- No credentials introduced anywhere.

## 5. Report

Short summary only -- no full file dumps: what changed (version, MCP
servers added/failed, TOML fields reconciled, `mcp_servers` deltas per
role), what was checked and found unchanged, what needs the user's
explicit decision (if anything), and validation pass/fail.

## Notes

- This skill mutates `{{CODEX_DIR}}/agents/`, `{{CODEX_DIR}}/orchestration.json`,
  `{{CODEX_DIR}}/orchestrator-spec/`, `{{CODEX_DIR}}/skills/`. Treat it like
  the destructive-adjacent maintenance it is: read before overwrite, edit
  narrowly, never blanket-regenerate files that haven't drifted.
- Does not touch `~/.codex/config.toml` beyond confirming the `[agents]`
  table (see §1/§3), does not install/update/repair any MCP server --
  discovery only, never remediation of third-party capabilities.
- If nothing has drifted, say so plainly and make no edits.
