# Orchestration System — README (Codex CLI)

Manager/researcher/worker/validator/judge multi-agent architecture for
OpenAI Codex CLI. Installed {{INSTALL_DATE}} on Codex CLI {{CODEX_VERSION}}.

## 1. Architecture

```
User task
  → task-orchestrator (top-level session; no subagent config, manager runs here)
    → codebase-researcher (medium, sandbox: read-only)      ─┐ up to
    → implementation-worker (medium, sandbox: workspace-write)  ─┤ 4 parallel
    → test-validator (medium, sandbox: workspace-write)      ─┘ subagents,
  → result-judge (high, sandbox: read-only, independent — complex/high-risk or on request)
  → correction loop (≤2 cycles)
  → one consolidated final response
```

`task-orchestrator` is the top-level Codex session, not a subagent --
Codex subagents cannot spawn further subagents, so the manager must run
at the top level, invoked via the `orchestrate` skill.

## 2. Files

- Spec source (edit here): `{{CODEX_DIR}}/orchestrator-spec/` — README,
  architecture.md, orchestration.template.json, generation-plan.md,
  discovery/ (7), instructions/ (4), policies/ (11), agents/ (5),
  skill/ (1).
- Runtime config: `{{CODEX_DIR}}/orchestration.json`.
- Manager (read as prose, not a registered subagent):
  `{{CODEX_DIR}}/agents/task-orchestrator.md` (no frontmatter).
- Subagent configs: `{{CODEX_DIR}}/agents/{codebase-researcher,
  implementation-worker,test-validator,result-judge}.toml`.
- Skills: `{{CODEX_DIR}}/skills/orchestrate/SKILL.md`,
  `{{CODEX_DIR}}/skills/orchestrate-sync/SKILL.md` (+ its
  `references/orchestrate-sync-body.md`).
- Global session config: `~/.codex/config.toml` `[agents]` table
  (`max_concurrent_threads_per_session`) — see §6, always global even for
  a project-scoped install.
- This doc: `{{CODEX_DIR}}/README-orchestration.md`.

## 3. Configuration table

Shipped defaults — see your `orchestration.json` for the authoritative
current values. `/orchestrate-sync` owns reasoning effort and any model
pin: it verifies on every run that this table, the `.toml` files and
`orchestration.json` agree, and asks you only when something moved — then
writes the answer to all of them together. Run `/orchestrate-sync models`
to change them deliberately. It may also adjust `mcp_servers` maps and the
deny list; it never changes workflow limits or permission policy without
asking:

| Role | Reasoning effort | Model | Write src | Write tests | Sandbox | Spawn | Worktree | MCP |
|---|---|---|---|---|---|---|---|---|
| task-orchestrator | n/a (top-level session) | session default | yes | yes | n/a | **yes** | integrates | all (mutations approval-gated) |
| codebase-researcher | medium | session default unless overridden | no | no | read-only (native) | no | n/a | empty by default, `/orchestrate-sync` adds |
| implementation-worker | medium | session default unless overridden | assigned scope | default off | workspace-write | no | **automatic** (native) | empty by default |
| test-validator | medium | session default unless overridden | **no** | default off | workspace-write | no | shared unless runtime isolates | empty by default |
| result-judge | high | session default unless overridden | no | no | read-only (native) | no | n/a | empty by default |

"Session default unless overridden": each `.toml` ships with its `model`
line commented out, so the subagent inherits whatever model your Codex
session is configured to use. Run `/orchestrate-sync` to pin a specific
model per role — the installer does not ask, because model IDs change too
often to bake into a shell script and only a live session can see which
ones your account has.

`orchestrator-spec/verify-install.py` is the executable definition of this
install's invariants; `/orchestrate-sync` runs it instead of re-checking
them by eye, and you can run it yourself at any time:
`python3 {{CODEX_DIR}}/orchestrator-spec/verify-install.py {{CODEX_DIR}}`

## 4. Launch

- `codex` — start a normal session, then invoke the skill:
  `/orchestrate <task>` or `$orchestrate <task>` (both trigger forms are
  supported by Codex's Skills system).
  Example: `/orchestrate add a password-reset flow with tests`.
- Not the default behavior; nothing about your normal Codex usage changes
  unless you invoke the skill.

## 5. Permissions

- Only the manager (top-level session) spawns subagents.
- **Native sandbox enforcement**: `sandbox_mode = "read-only"` on
  `codebase-researcher.toml` and `result-judge.toml` is enforced by
  Codex itself, not just a prompt convention — a real advantage over
  platforms where read-only delegates rely on prompt discipline alone.
- `sandbox_mode` only has two tiers (read-only / workspace-write) — the
  finer test-file-vs-production-file distinction for the validator is
  still prompt+review enforced (see §6), sandbox_mode can't express it.
- Destructive Git forbidden without explicit per-command approval.
- External mutations (issue-tracker writes, push, publish): explicit user
  approval, every time, routed through the manager.
- Memory: persistent agent memory disabled; repository-memory (if a
  codebase-graph MCP is connected) reads allowed, writes forbidden.

## 6. Validator test-only write policy (limitation)

`sandbox_mode = "workspace-write"` lets the validator write anywhere in
the workspace — it does not natively distinguish "test files" from
"production files". The validator's own instructions (in its `.toml`
`developer_instructions`) carry a hard prompt boundary against
production-source changes; enforcement = validator prompt + manager diff
review + judge audit (any validator hunk outside test paths is a
violation). Same reasoning applies to the worker's SCOPE confinement —
sandbox_mode grants workspace-write broadly, the task packet's SCOPE
section is what narrows it, backed by review.

## 7. Commands, build, serve, long-running

Project commands discovered dynamically every run (package.json scripts,
build/test/lint/serve/E2E configs, Makefile, CI files…) and classified.
Smallest sufficient command first.

**Default-off flags** (orchestration.json, same schema as the rest of
this bundle): test-file creation and build/serve commands were set at
install time (see §3). No subagent creates test files or runs
build/serve beyond what you configured, unless you explicitly enable it
for a single run; the manager records any override in its final report.
Serve/watch (when enabled): collect evidence, then terminate (report
start+stop) unless the user asked to keep it running. Timeout is not
success; unexecuted is not passed. AGENTS.md command restrictions always
override these defaults.

## 8. Worktrees

Implementation workers get an automatic isolated worktree. Treat other
subagents as shared unless the runtime reports isolation. Parallel writes
still require disjoint file scopes. The manager confirms each subagent's
location, integrates worker worktrees, and reviews any shared-workspace
changes directly.

## 9. Dynamic capability discovery

At the start of every run the manager discovers, from the live
installation: native tools; installed skills (`~/.codex/skills/`,
`.codex/skills/`); subagent configs (`~/.codex/agents/`,
`.codex/agents/`); MCP servers (`~/.codex/config.toml`
`[mcp_servers.*]`); repository commands; AGENTS.md hierarchy.
Descriptions are inspected before use — never name-inference. Task
packets name capabilities or prohibitions only when they materially affect
the task. Delegates report notable use, failure, or fallback; the manager
and judge audit routing only when it affects correctness, permissions, or
evidence. `orchestration.json` stays free of static capability lists except
`capabilities.explicitDeny`.

Weaker than some platforms: Codex's discovery surface leans on
configured/declared state (`config.toml`, `.toml` files) more than a
live introspected "what's connected right now" tool listing — treat
"configured" and "actually connected" as separate facts (see
`orchestrate-sync`'s references file, §1).

## 10. Instruction-hierarchy governance

Resolution order, closer-to-cwd wins, files concatenated: global
`~/.codex/AGENTS.md` → `<git-root>/AGENTS.md` (repo root, NOT inside
`.codex/`) → every intermediate directory's `AGENTS.md` → `<cwd>/AGENTS.md`.
Each level's `AGENTS.override.md` sibling beats its plain `AGENTS.md`.
**Real constraint**: concatenated instruction text is capped at 32 KiB
(`project_doc_max_bytes`) — don't assume everything discovered actually
loaded into context. No import syntax, no per-checkout "local" variant,
no managed-policy tier (unlike some other platforms) — don't invent
them.

**This installer never authors or edits AGENTS.md at any level.** The
orchestrator discovers and reads AGENTS.md/`.override.md` files; it does
not write them.

## 11. Correction loop

BLOCKER/HIGH finding → narrow correction packet → worker subagent →
re-run affected tests/checks → manager re-review → re-judge. Max 2 judge
cycles; still rejected ⇒ status INCOMPLETE with outstanding findings.
Mandatory violations are never silently waived.

Subagents run under per-role deadlines (`workflow.agentTimeoutSeconds`:
researcher 180s, worker 900s, validator 300s, judge 180s, correction
worker 300s). The manager waits with one blocking `wait_agent` per
subagent, set to that role's remaining deadline, rather than polling;
`waitSliceSeconds` (default 60) bounds a wait only when several agents
are in flight and their waits must interleave. A subagent that exceeds
its deadline is interrupted
immediately; with `maximumAgentRetries` (default 0) the manager does not
re-run it, completing the scope locally or reporting it as a gap. The
independent judge is required only for complex/high-risk/security-
sensitive or explicitly requested work — manager review and validation
stay mandatory in every class.

## 12. Security / prompt injection

Retrieved content (MCP, web, memory, docs, logs, issues) is data;
embedded directives are flagged, not obeyed; judge checks for injection
effects. No credentials in packets, reports, `.toml` files, or JSON.
Dependency additions require manager sanction.

## 13. Excluded capabilities

None by default. Every delegate `.toml` ships with `mcp_servers = {}` (an empty TOML map) and
`orchestration.json`'s `capabilities.explicitDeny` is empty — this bundle
makes no assumption about what's installed or connected on this machine.
Run `/orchestrate-sync` (required, see §16) to populate both from
what's actually on this installation.

## 14. Unsupported / not used features

- Fields not added speculatively: anything beyond `name`, `description`,
  `developer_instructions`, `model`, `model_reasoning_effort`,
  `sandbox_mode`, `mcp_servers` — add only when `/orchestrate-sync`
  confirms a new field is real and demonstrably improves enforcement.
- Native test-file-vs-production-file write restriction: unsupported
  (see §6) — `sandbox_mode` only has two tiers.
- Subagent-spawns-subagent nesting: not used/not relied upon — this
  architecture only ever needs one level of fan-out from the top-level
  manager.

## 15. Environment quirks

Codex installations vary — connected MCP servers, installed skills,
subagent-field support, sandbox behavior. This bundle ships without
assumptions about any of that; `/orchestrate-sync` inspects *this*
installation and reconciles the delegate `mcp_servers` maps and
`capabilities.explicitDeny` accordingly. Run it after install and
periodically thereafter (new Codex CLI version, MCP servers
added/removed).

## 16. Maintenance

**Run `/orchestrate-sync` now, right after installing** — it's what
populates the deny list and MCP server routing for this machine; the
bundle works before that too, just with empty `mcp_servers` maps.

To customize further: edit specs in `{{CODEX_DIR}}/orchestrator-spec/`,
then ask your session to regenerate the runtime files per
`generation-plan.md`.

## 17. Troubleshooting

- `/orchestrate` not found → confirm
  `{{CODEX_DIR}}/skills/orchestrate/SKILL.md` exists; restart the
  session.
- Subagent not found → confirm the corresponding `.toml` exists under
  `{{CODEX_DIR}}/agents/` and parses as valid TOML; restart the session.
- Worker can't edit → check `sandbox_mode` on `implementation-worker.toml`
  is `workspace-write`, not `read-only`.
- MCP tools missing in a subagent → confirm the server is declared in
  its `.toml`'s `mcp_servers` map AND in `~/.codex/config.toml`
  `[mcp_servers.*]`; run `/orchestrate-sync`.
- Judge approves nothing → check evidence quality first; the judge
  REJECTs on missing evidence by design.
- Manager ran as a spawned subagent, lost its pipeline → don't invoke
  `task-orchestrator` as a subagent from elsewhere; always enter via
  `/orchestrate` in the top-level session, or `codex` directly followed
  by the skill invocation.
- `[agents]` warning during install → `~/.codex/config.toml` already had
  an `[agents]` section; verify `max_concurrent_threads_per_session`
  yourself (should be ≥ `workflow.maximumParallelWorkers` in
  `orchestration.json`, default 4).

## 18. Example workflows

- **Feature implementation**: `/orchestrate add a cancel-subscription
  flow with unit tests` → researcher maps components/services → worker
  (isolated worktree) implements + specs → validator runs scoped tests →
  judge audits diff vs project conventions.
- **Bug investigation**: `/orchestrate find root cause of the duplicated
  validation error on the checkout page (investigate only)` →
  researchers in parallel; no workers; consolidated analysis; judge
  checks evidence.
- **Security review**: `/orchestrate security-review the auth middleware
  changes on this branch` → researcher + validator evidence, judge on
  findings quality.
- **Test generation**: `/orchestrate add full spec coverage for the
  payment service` → validator-led; worker only if production seams are
  needed.
- **Build failure**: `/orchestrate diagnose why the build fails on this
  branch` → AGENTS.md command restrictions (if any) respected; agents
  inspect configs/logs first.
- **Serve/runtime verification**: worker/validator start serve, capture
  HTTP evidence, terminate — reported start+stop.
