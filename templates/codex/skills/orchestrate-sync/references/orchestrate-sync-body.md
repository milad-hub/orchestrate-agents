# Orchestrate Sync

Full procedure (Codex CLI). Maintenance skill for the orchestrate system in
`{{CODEX_DIR}}/orchestrator-spec/`. Read-only discovery, then targeted edits
only where drift is found -- never a blind full regenerate.

`PY` below means the first of `python3`, `python`, `py -3` that runs. On
Windows `python3` is frequently absent; do not conclude Python is missing
until all three have failed.

## Procedure

### 0. Fast path

Most runs find nothing. Establish that cheaply before spending anything, and
let the verifier do the ordering -- it migrates before it checks, and records
the prompt hashes before anything can edit them.

1. Run, with the version string `codex --version` prints:
   `PY {{CODEX_DIR}}/orchestrator-spec/verify-install.py --sync-start {{CODEX_DIR}} --cli-version "<version>"`
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
  did change, prefer the documented Codex custom-agent schema -- `name`,
  `description`, `developer_instructions`, `model`, `model_reasoning_effort`,
  `sandbox_mode`, `mcp_servers`, `skills.config` -- and sample
  `~/.codex/agents/*.toml` only to corroborate it. Another tool's agent file
  is evidence of what that tool wrote, not of what Codex supports.
- Model naming for this account: model IDs change often, so treat a stale
  pin as something to raise in step 3, never to rewrite in passing.

### 2. Diff against the spec's recorded state

Compare live findings to what is currently written in:
- `orchestrator-spec/install-state.json` (platform, bundle version, last
  seen CLI version and check date)
- `orchestrator-spec/generation-plan.md` (version-support notes)
- `orchestration.json` (`capabilities.explicitDeny`)
- `README-orchestration.md`'s "Excluded capabilities" and "Unsupported / not
  used features" sections -- by name, not by section number; the numbering
  shifts.
- Each delegate's `mcp_servers` map in `{{CODEX_DIR}}/agents/*.toml`

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
- If a previously-unsupported TOML field is now confirmed supported (or vice
  versa), update `generation-plan.md`'s version-support notes AND the
  relevant `.toml` file(s) -- but only add a field if the documented schema
  confirms it and it demonstrably improves enforcement; don't speculatively
  add fields.
- **Removing** a server from a delegate's `mcp_servers` map -- because it is
  gone or disabled -- is automatic: it only ever narrows what a delegate can
  reach. **Adding** one is not. List proposed additions in the report with
  the role and the reason, and apply them only after the user agrees, even
  when the server looks read-only and fits the role's `sandbox_mode`
  envelope. Inspect its tool descriptions; never infer from its name.
- Never widen a delegate's `sandbox_mode`, and never invent a field that
  would let a subagent spawn further subagents.
- Never edit a delegate's `developer_instructions`. Step 4 hashes it. The
  surrounding TOML keys are yours; the prompt prose is not. A deliberate
  prompt change is a re-bless, not a silent edit.
- Model and reasoning effort: **verify, don't interrogate.** Step 4's
  verifier already proves that each `.toml`, `orchestration.json` and the
  README configuration table agree. Raise the question with the user only
  when: the verifier reports a disagreement; a pinned model no longer exists
  on this account; a materially better option has appeared; or the user
  asked for it (`/orchestrate-sync models`). Otherwise state the current
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
  `sandbox_mode` is not the lever here and must not be widened for it. Step
  4's verifier fails if these disagree, so never leave them half-done.
- Never touch: workflow limits (`maximumParallelWorkers`,
  `maximumCorrectionCycles`), permission policy, memory settings,
  `defaultGlobalAgent: false`, or `~/.codex/config.toml`'s `[agents]` values
  -- these are user decisions, not discovery outputs. If the installation
  seems to demand a change here, stop and ask instead of changing it
  silently.

### 4. Validate

1. Run `PY {{CODEX_DIR}}/orchestrator-spec/verify-install.py --sync-finish {{CODEX_DIR}}
   --cli-version "<version>"`. It re-runs every check and, only if they all
   pass, records `cliVersion` and `lastCheckedAt` for you -- so a run that
   ends broken cannot leave a state file claiming it succeeded. Fix what it
   names and re-run until it prints `NEXT: DONE`.
2. What it checks is in `verify-install.py`: JSON policy invariants, the
   fanned-out permission flags agreeing, every `.toml` parsing with the right `sandbox_mode`, three-way model/effort
   agreement, each role's mandatory prompt blocks, the blessed prompt-body
   hashes, leftover installer tokens and credential-shaped strings -- across
   this bundle's own files only. That file is the list; a prose copy here is
   what goes stale. Without Python, work through it by reading that file.
3. Confirm the `orchestrate` and `orchestrate-sync` skills still appear in
   the runtime skills listing with valid frontmatter. The verifier reads
   files; only the runtime can see the live registry.

### 5. Report

Short summary only -- no file dumps: what changed (version, MCP servers, TOML
fields, `mcp_servers` deltas per role), any server additions awaiting the
user's approval, the current model/effort assignment in one line, what was
checked and found unchanged, what needs the user's explicit decision, and the
verifier's result.

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
