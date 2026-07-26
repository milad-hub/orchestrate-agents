# orchestrate-agents

A manager/researcher/worker/validator/judge multi-agent orchestration
system for [Claude Code](https://claude.com/claude-code) and
[Codex CLI](https://developers.openai.com/codex) — one spec, two
generators, install either or both.

```
User task
  → task-orchestrator (manager) — plan, discover capabilities, route, delegate, review
    → codebase-researcher    ─┐ up to 4 parallel
    → implementation-worker  ─┤ agents, disjoint
    → test-validator         ─┘ file scopes only
  → result-judge — independent, read-only review
  → correction loop (up to 2 cycles)
  → one consolidated final response
```

The manager discovers whatever tools, skills, agents, and MCP servers are
actually available in the current session and routes them to the right
delegate for each subtask — it never assumes a fixed toolset. Read-only
research runs in parallel; worker writes are worktree-isolated and all
writes are scoped and reviewed; a validator checks the result; an
independent judge reviews both the work and the manager's own process
before anything is reported done.

## Requirements

- [Claude Code](https://claude.com/claude-code) and/or
  [Codex CLI](https://developers.openai.com/codex) installed and on
  `PATH` (the installer checks versions but doesn't require either to
  run at install time).
- bash (macOS/Linux/WSL/git-bash) **or** PowerShell 5.1+ (Windows).
- No other runtime dependency — this bundle is plain markdown, JSON, and
  (for Codex) TOML, no compiled binary, no Node/Python package to
  install.

## Install

Clone or download this repo, then from inside it run:

```bash
./install.sh
```

or, on Windows:

```powershell
.\install.ps1
```

You'll be asked:
1. **Platform** — Claude Code, Codex CLI, or Both.
2. **Install scope** — globally (`~/.claude` and/or `~/.codex`, available
   in every project) or into one specific project's `.claude/`/`.codex/`
   directory. (Note: for Codex, the `[agents]` concurrency setting always
   goes in the global `~/.codex/config.toml` even for a project-scoped
   install — Codex has no per-project config file for it. Your existing
   `config.toml` is never overwritten; an existing `[agents]` table is
   left untouched with a warning.)

That's the whole interview — two questions, plus a confirmation if an
existing install is about to be overwritten.

Everything else ships as a working default. **Test-file writes and
build/serve commands are OFF**, because widening a permission is a
deliberate decision, not a question to answer while skimming an
installer. Turn them on the same way you change anything else after
install — run `/orchestrate-update`, which flips the flag in
`orchestration.json` and the validator's tool allowlist together, so the
two can't disagree. For scripted installs, `ORCH_ALLOW_TEST_WRITES=y`
and `ORCH_ALLOW_BUILD_SERVE=y` still set them up front.

The installer does **not** ask about models or effort either. Those ship as
working defaults — manager opus/high, researcher haiku/medium, worker
sonnet/medium, validator haiku/medium, judge sonnet/high — and
`/orchestrate-update` owns them from there. It *verifies* them on every
run (the shipped `orchestrator-spec/verify-install.py` checks that the
agent frontmatter, `orchestration.json` and the README table all agree)
and raises the question with you only when something actually moved: a
disagreement, a model that no longer exists on your account, or a better
tier appearing. Run `/orchestrate-update models` to change them
deliberately. (The
manager's model only binds under `claude --agent task-orchestrator`;
`/orchestrate` adopts the manager role in your current session, so it
runs on that session's model. Codex delegates ship with no model pinned
and inherit the Codex session model.)

Everything else (parallelism limits, permission policy, worktree
isolation, correction-loop limits) ships as fixed, safe defaults — see
the installed `README-orchestration.md` for the full rationale.

**Required next step:** open a session and run

```
/orchestrate-update
```

This bundle ships with **no assumptions** about what's installed on your
machine — no plugins, no MCP servers, no failed/disabled capabilities are
pre-baked in, and every Codex subagent ships with an empty `mcp_servers`
map (table). `/orchestrate-update` inspects *your* live installation once and
reconciles the delegate agents' tool allowlists (Claude) or `mcp_servers`
tables (Codex) and the capability deny-list accordingly. The system works
before you run it too, just conservatively.

## Use it

```
/orchestrate <task>
```

runs the full pipeline inline in your current session. On both
platforms, the manager runs as the *top-level session*, never as a
spawned subagent/delegate — subagents can't spawn further subagents on
either platform, so `/orchestrate` makes the current session adopt the
manager role directly and dispatch the 4 delegates itself. On Claude
Code you can also launch straight into manager mode:

```
claude --agent task-orchestrator
```

Full documentation (architecture, permissions model, capability routing,
instruction-hierarchy governance, troubleshooting, example workflows) is
installed alongside the bundle at `README-orchestration.md` in whichever
directory/directories you installed it into.

## Repo layout

```
install.sh / install.ps1   — installers (see above)
templates/
  orchestrator-spec/       — shared spec source (edit + regenerate),
                              platform-neutral, used by both generators
  agents/                  — the 5 Claude Code agent definitions
  skills/                  — Claude Code /orchestrate and /orchestrate-update
  README-orchestration.template.md   — Claude Code doc template
  codex/
    agents/                — 4 Codex subagent .toml configs + the
                              manager's task-orchestrator.md (read as
                              prose, not a registered subagent)
    skills/                — Codex /orchestrate and /orchestrate-update
                              (the latter's long procedure lives in
                              references/orchestrate-update-body.md)
    README-orchestration.template.md   — Codex CLI doc template
```

## Updating an existing install

Re-run the installer (it will ask before overwriting), or edit the
installed `orchestrator-spec/` directly and ask your session to
regenerate per its `generation-plan.md`. Run `/orchestrate-update`
periodically to keep the capability deny-list and tool/MCP routing in
sync with your installation as it changes.

## License

MIT — see [LICENSE](LICENSE).
