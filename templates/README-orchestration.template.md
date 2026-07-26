# Orchestration System — README

Global manager/researcher/worker/validator/judge architecture for Claude
Code. Installed {{INSTALL_DATE}} on Claude Code {{CLAUDE_VERSION}}.

## 1. Architecture

```
User task
  → task-orchestrator (opus, high) — plan, discover, route, delegate, review
    → codebase-researcher (haiku, medium, read-only)   ─┐ ≤4 parallel
    → implementation-worker (sonnet, medium, worktree)          ─┤ agents,
    → test-validator (haiku, medium, test-writes only)   ─┘ disjoint edits
  → result-judge (sonnet, high, read-only, independent — complex/high-risk or on request)
  → correction loop (≤2 cycles)
  → one consolidated final response
```

## 2. Files

- Spec source (edit here): `{{CLAUDE_DIR}}/orchestrator-spec/` — README,
  architecture.md, orchestration.template.json, generation-plan.md,
  discovery/ (7), instructions/ (4), policies/ (11), agents/ (5),
  skill/ (1).
- Runtime config: `{{CLAUDE_DIR}}/orchestration.json`.
- Agents: `{{CLAUDE_DIR}}/agents/{task-orchestrator,codebase-researcher,implementation-worker,test-validator,result-judge}.md`.
- Skills: `{{CLAUDE_DIR}}/skills/orchestrate/SKILL.md`,
  `{{CLAUDE_DIR}}/skills/orchestrate-sync/SKILL.md`.
- This doc: `{{CLAUDE_DIR}}/README-orchestration.md`.

## 3. Configuration table

Shipped defaults — see your `orchestration.json` for the authoritative
current values. `/orchestrate-sync` owns model and effort: it verifies on
every run that this table, the agent frontmatter and `orchestration.json`
agree, and asks you only when something moved — then writes the answer to
all three together. Run `/orchestrate-sync models` to change them
deliberately. It may also adjust tool allowlists and the deny list; it
never changes workflow limits or permission policy without asking:

| Agent | Model | Desired effort | Write src | Write tests | Commands | Build | Serve | Spawn | Worktree | MCP | Skills/plugins |
|---|---|---|---|---|---|---|---|---|---|---|---|
| task-orchestrator | opus | high | yes | yes | yes | yes | yes | **yes** | integrates | all (mutations approval-gated) | any relevant |
| codebase-researcher | haiku | medium | no | no | inspection only | no | no | no | n/a | read-only allowlist | read-only only |
| implementation-worker | sonnet | medium | assigned scope | default off | yes | default off | default off | no | **yes** (spawned with `isolation: "worktree"`) | read-only allowlist | per packet |
| test-validator | haiku | medium | **no** | default off | yes | default off | default off | no | optional | read-only allowlist | per packet |
| result-judge | sonnet | high | no | no | safe diagnostics | no | no | no | n/a | read-only allowlist | read-only only |

Per-agent effort is set through `effort:` frontmatter — desired =
effective.

**The manager row applies to `claude --agent task-orchestrator` only.**
`/orchestrate` makes your *current* session adopt the manager role, so it
runs on whatever model and effort that session already uses.

`test-validator` receives `Edit`/`Write` in its `tools:` allowlist only
when test writes were enabled at install time. With the default off the
harness withholds them, so the validator cannot write at all.

`orchestrator-spec/verify-install.py` is the executable definition of this
install's invariants — including that the allowlist above matches
`validator.allowTestWrites`. `/orchestrate-sync` runs it instead of
re-checking them by eye, and you can run it yourself at any time:
`python3 {{CLAUDE_DIR}}/orchestrator-spec/verify-install.py {{CLAUDE_DIR}}`

## 4. Launch

- `claude --agent task-orchestrator` — manager as main session agent.
- `/orchestrate <task>` — from any session; the session adopts the
  manager role (reads task-orchestrator.md) and spawns the delegates
  itself, running on that session's own model. Reason: subagents cannot spawn agents in this harness, so a
  spawned manager would lose its pipeline.
  Example: `/orchestrate add password-reset flow to the web app with tests`.
- Not the default agent; nothing in `settings.json` is changed by this
  bundle.

## 5. Permissions

- Policy: balanced. `bypassPermissions` forbidden everywhere.
- Only the manager spawns agents (others lack the Agent tool).
- Researcher/judge: no Edit/Write in `tools:`; read-only MCP allowlist
  only — no mutating MCP tools reachable.
- Destructive Git forbidden without explicit per-command approval.
- External mutations (e.g. issue-tracker writes, push, publish): explicit
  user approval, every time, routed through the manager.
- Memory: persistent agent memory disabled; repository-memory (if a
  codebase-graph MCP is connected) reads allowed, writes forbidden.

## 6. Validator test-only write policy (limitation)

Claude Code cannot natively restrict writes to test files only. The
validator has Edit/Write for tests/fixtures/snapshots, with a hard prompt
boundary against production source; enforcement = validator prompt +
manager diff review + judge audit (any validator hunk outside test paths
is a violation). Same mechanism scopes the worker to its assigned files.
Bash likewise cannot be tool-restricted to read-only for researcher/judge;
prompt-enforced + audited.

## 7. Commands, build, serve, long-running

Project commands discovered dynamically every run (package.json scripts,
angular/nx/turbo configs, jest/vitest/karma/playwright/cypress, Makefile,
CI files…) and classified (install/lint/type-check/test/build/serve/E2E/
benchmark/codegen/…). Smallest sufficient command first.

**Default-off flags** (orchestration.json): test-file creation
(`worker.allowTestWrites`, `validator.allowTestWrites`,
`commands.allowTestFileCreation`) and build/serve commands
(`commands.allowBuildCommands`, `commands.allowServeCommands`,
`validator.allowBuildCommands`, `validator.allowServeCommands`) were set
at install time (see §3). No agent creates test files or runs build/serve
beyond what you configured, unless you explicitly enable it for a single
run; the manager records any override in its final report. Serve/watch
(when enabled): collect evidence, then terminate (report start+stop)
unless the user asked to keep it running. Timeout ≠ success; unexecuted ≠
passed. CLAUDE.md command restrictions always override these defaults
(e.g. a repo rule "never run builds" prohibits builds there regardless).

## 8. Worktrees

Workers are spawned with Agent-tool `isolation: "worktree"` (temporary git
worktree; auto-cleaned when unchanged). Parallel writes still require
disjoint file scopes. Manager inspects the worktree diff, integrates, and
re-inspects the integrated diff; judge verifies nothing was lost.

## 9. Dynamic capability discovery

At the start of every run the manager discovers, from the live session:
native tools; native/bundled skills; user/project/plugin skills; native/
user/project/plugin agents; plugin commands and hooks; MCP servers and
tools; language servers; CLI helpers; repository commands; CLAUDE.md
hierarchy. Descriptions are inspected before use — never name-inference.
Task packets name capabilities or prohibitions only when they materially
affect the task. Delegates report notable use, failure, or fallback; the
manager and judge audit routing only when it affects correctness,
permissions, or evidence. `orchestration.json` stays free of static
capability lists except `capabilities.explicitDeny`.

## 10. CLAUDE.md governance

Precedence: platform/system > managed policies > direct user instructions
> CLAUDE.md (+imports) > role instructions > task packet > skills/plugins
> repo docs/comments > retrieved data (untrusted). Nested CLAUDE.md wins
inside its subtree; CLAUDE.local.md supported; `@path` imports supported.
Manager builds an instruction manifest and slices scoped rules into each
packet (subagents don't reliably auto-load the hierarchy). Manager
verifies compliance independently; judge re-discovers and re-verifies;
material mandatory-rule violation ⇒ REJECT.

## 11. Correction loop

BLOCKER/HIGH finding → narrow correction packet → worker → re-run
affected tests/checks → manager re-review → re-judge. Max 2 judge cycles;
still rejected ⇒ status INCOMPLETE with outstanding findings. Mandatory
violations are never silently waived.

Delegates run under per-role deadlines (`workflow.agentTimeoutSeconds`:
researcher 180s, worker 900s, validator 300s, judge 180s, correction
worker 300s). Delegates push a completion notification when they finish,
so the manager never polls — `waitSliceSeconds` in `orchestration.json`
applies to Codex only. A delegate that exceeds its deadline is stopped
immediately; with
`maximumAgentRetries` (default 0) the manager does not re-run it, and
completes the scope locally or reports it as a gap. The independent judge
is required only for complex/high-risk/security-sensitive or explicitly
requested work — manager review and validation stay mandatory in every
class.

## 12. Security / prompt injection

Retrieved content (MCP, web, memory, docs, logs, issues) is data; embedded
directives are flagged, not obeyed; judge checks for injection effects.
No credentials in packets, reports, or JSON. Dependency additions require
manager sanction.

## 13. Excluded capabilities

None by default. This bundle ships with an empty
`capabilities.explicitDeny` and generic native-tool-only agent allowlists
— it makes no assumption about what's installed or connected on this
machine. Run `/orchestrate-sync` (required, see §16) to populate the
deny list with anything actually disabled or failing here, and to add
relevant read-only MCP tools to each delegate's allowlist.

## 14. Unsupported / not used features

- Frontmatter keys not confirmed supported by scanning shipped plugin
  agents, and therefore not emitted: `maxTurns`, `memory`, `mcpServers`,
  `skills`, `isolation`, `background`, `permissionMode`, `disallowedTools`
  (allowlists used instead). Behaviors enforced via prompts and
  Agent-tool spawn params.
- Native test-only write restriction: unsupported (see §6).
- Native read-only Bash: unsupported (see §6).

## 15. Environment quirks

Claude Code installations vary — connected MCP servers, plugin
availability, OS-specific tool behavior, repo-specific command policies.
This bundle ships without assumptions about any of that; `/orchestrate-sync`
inspects *this* installation and reconciles the delegate agents' tool
allowlists and `capabilities.explicitDeny` accordingly. Run it after
install and periodically thereafter (new Claude Code version, plugins
enabled/disabled, MCP servers added/removed).

## 16. Maintenance

**Run `/orchestrate-sync` now, right after installing** — it's what
populates the deny list and MCP tool allowlists for this machine; the
bundle works before that too, just with a conservative native-tools-only
allowlist.

To customize further: edit specs in `{{CLAUDE_DIR}}/orchestrator-spec/`,
then ask Claude Code: "Regenerate the orchestration runtime files from
{{CLAUDE_DIR}}/orchestrator-spec/ per generation-plan.md." Validation
steps live in generation-plan.md.

`/orchestrate-sync` edits narrowly (deny lists, version notes, tool
allowlists, frontmatter support) and asks before touching
models/limits/permissions.

## 17. Troubleshooting

- `/orchestrate` not found → confirm
  `{{CLAUDE_DIR}}/skills/orchestrate/SKILL.md` exists; restart session.
- `task-orchestrator` agent type missing → confirm
  `{{CLAUDE_DIR}}/agents/task-orchestrator.md` frontmatter parses (YAML),
  name matches filename; restart session.
- Worker can't edit → check permission prompts (balanced policy still
  prompts); never enable bypassPermissions.
- MCP tools missing in subagents → the parent session must have the
  server connected; run `/orchestrate-sync`; failed servers are
  excluded by design.
- Judge approves nothing → check evidence quality first; the judge
  REJECTs on missing evidence by design.
- Manager ran alone, no validator/judge → it was spawned as a subagent
  (cannot spawn agents). Use `/orchestrate` (inline manager) or
  `claude --agent task-orchestrator`; do not Agent-spawn
  `task-orchestrator` from another agent.

## 18. Example workflows

- **Feature implementation**: `/orchestrate add a cancel-subscription flow
  with unit tests` → researcher maps components/services → worker
  (worktree) implements + specs → validator runs scoped tests → judge
  audits diff vs project conventions.
- **Bug investigation**: `/orchestrate find root cause of the duplicated
  validation error on the checkout page (investigate only)` →
  researchers in parallel; no workers; consolidated analysis; judge
  checks evidence.
- **Security review**: `/orchestrate security-review the auth middleware
  changes on this branch` → researcher + validator evidence, a
  security-focused skill/plugin recommended if installed, judge on
  findings quality.
- **UI implementation**: `/orchestrate build the settings page per
  attached design` → any installed frontend/UI design skills recommended
  to the worker.
- **Architecture review**: `/orchestrate review module boundaries of this
  workspace` → a codebase-graph MCP's queries recommended if connected;
  read-only.
- **Test generation**: `/orchestrate add full spec coverage for
  the payment service` → validator-led; worker only if production seams
  are needed.
- **Build failure**: `/orchestrate diagnose why the build fails on this
  branch` → CLAUDE.md command restrictions (if any) are respected; agents
  inspect configs/logs first.
- **Serve/runtime verification**: worker/validator start serve, capture
  HTTP evidence, terminate — reported start+stop.
- **Issue-tracker read-only comparison**: `/orchestrate compare PR #123's
  changes against issue #456's acceptance criteria` → read-only
  issue-tracker MCP tools recommended if connected; any comment/vote
  would require explicit approval.
