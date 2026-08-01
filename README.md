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
- `git` on `PATH` — implementation workers run in isolated worktrees.
- `python3` (3.7+) on `PATH` — `verify-install.py` and the settings UI.
  Without it `/orchestrate-sync` falls back to checking by hand.
- No package to install — this bundle is plain markdown, JSON, and (for
  Codex) TOML, no compiled binary, no Node or PyPI dependency. The
  installer checks all of the above up front and tells you what would
  break before it writes anything.

## Install

```bash
git clone https://github.com/milad-hub/orchestrate-agents.git
cd orchestrate-agents
./install.sh
```

or, on Windows:

```powershell
git clone https://github.com/milad-hub/orchestrate-agents.git
cd orchestrate-agents
.\install.ps1
```

Downloading the ZIP works too — the installer only reads `templates/`
and never calls `git` on itself.

Before it writes anything, the installer checks this machine for `git`,
`python3` (3.7+) and the CLI for the platform you picked, and tells you
what would break if one is missing.

You'll be asked:
1. **Platform** — Claude Code, Codex CLI, or Both.
2. **Install scope** — globally (`~/.claude` and/or `~/.codex`, available
   in every project) or into one specific project's `.claude/`/`.codex/`
   directory. (Note: for Codex, the `[agents]` concurrency setting always
   goes in the global `~/.codex/config.toml` even for a project-scoped
   install — Codex has no per-project config file for it. Your existing
   `config.toml` is never overwritten; an existing `[agents]` table is left
   untouched, and the installer only says anything if
   `max_concurrent_threads_per_session` is below 8 — the ceiling the
   settings UI can select, not the 4 delegates the manager plans for by
   default. Codex only ever runs what the manager asks for, so a higher
   cap costs nothing and a lower one silently shrinks the fan-out.)

That's the whole interview — two questions, plus a confirmation if an
existing install is about to be overwritten.

If orchestrate is **already installed**, the installer says so and offers a
menu before asking anything else:

```
Orchestrate is already installed:
  C:\Users\you\.claude
  C:\Users\you\.codex

What next? (Up/Down move, Enter confirm):
  > (x) Reinstall or upgrade (keeps your orchestration.json)
    ( ) Open the settings UI
    ( ) Uninstall
```

It looks in the global targets and in the current directory, so a
project-scoped install is found by re-running the installer inside that
project.

### Upgrading

Re-run the installer over an existing install. The generated tree — agents,
skills, spec, README — is replaced; that is what upgrading means. Your
`orchestration.json` is **kept**, because it holds the models, effort,
permission flags and capability deny list `/orchestrate-sync` reconciled
for your machine, and the installer says so when it keeps it.

Agent `tools:` allowlists and Codex `mcp_servers` maps *are* regenerated, on
purpose: re-deriving them against your current plugins and servers is
`/orchestrate-sync`'s job, and carrying a stale allowlist forward would
resurrect entries for things that have since disappeared. So run
`/orchestrate-sync` after an upgrade. It also re-blesses the prompt-body
hashes, which the installer clears so a new bundle's prompts don't look like
tampering.

### Settings UI

The installer offers to open it at the end, and it stays available:

```bash
python3 ~/.claude/orchestrator-spec/config-ui.py
```

A local page on `127.0.0.1` with one tab per installed platform — both tabs
from either copy, since `.claude` and `.codex` sit next to each other. Settings
are grouped (models and effort, permissions and writes, workflow and review,
timeouts, memory, capabilities), each with a description and a toggle, number,
dropdown or list box.

At the top of each tab is one dial from **Swift** to **Exhaustive**:

| | Swift | Balanced *(ships)* | Thorough | Exhaustive |
|---|---|---|---|---|
| Researcher | never | auto | auto | always |
| Judge | never | auto | always | always |
| Validation | never | auto | always | always |
| Parallel workers | 1 | 4 | 4 | 6 |
| Correction cycles | 0 | 2 | 3 | 5 |
| Deadlines | ×0.6 | ×1 | ×1.5 | ×2 |

Plus a model and effort per role (effort only on Codex). Picking a stop applies
every one of those settings at once, re-runs the verifier, and **puts them all
back if it fails** — instant apply is only safe with an automatic undo. There is
also a **Revert** button for the rest of the session.

### Backup and restore

**Export** writes every synced install's settings to one JSON file — both
platforms from either tab. **Import** reads one back, writing each value
everywhere it has to agree and re-running the verifier, with the same
all-or-nothing rollback the profile dial uses.

What travels is what you chose: models, effort, policies, limits, deadlines.
What does not travel is everything `/orchestrate-sync` derived — tool
allowlists, MCP routing, prompt hashes — because those describe the machine
that produced them. Import them onto a different machine and the delegates
would name servers that are not there while missing the ones that are.

So on a fresh machine: install, import, and run `/orchestrate-sync` — in
either order, since the two write disjoint sets of keys. Import is a head
start on re-tuning forty settings, not a substitute for reconciling, and the
page says so when it finishes. It is the one control shown above the sync
gate, because a machine that has never synced is exactly where a restore
starts. Anything the file cannot carry is listed rather than dropped in
silence — a pinned permission flag reports as refused, another platform's
rows as not applicable, a typo as unknown.

Three things worth knowing:

- **A profile can never widen a permission.** Profiles write an explicit list
  of keys; `permissions`, `capabilities`, `memory` and the
  test-write/build/serve flags are not on it, and a test asserts those bytes
  are unchanged after applying all four.
- **The active profile is derived, not stored.** Change one setting afterwards
  and the dial reads **Custom** — a stored label would go stale and lie.
- **No profile ever asks you to re-sync.** Profiles write models, effort,
  deadlines and policy; tool allowlists and MCP routing are
  `/orchestrate-sync`'s business and no profile touches them. An earlier
  version warned when a role was switched back on, which turned out to be a
  warning with no true case — the skill reconciles all five delegates
  whatever the policies say.

**Nothing is shown until `/orchestrate-sync` has run.** Before that, the tool
allowlists, MCP routing and capability deny list are the bundle's defaults
rather than anything derived from your machine, so the tab shows the
instruction and a *Check again* button instead of settings. A banner over live
controls would still be asking you to trust the numbers under it. The
endpoint refuses writes in that state too, so the rule is a guarantee rather
than a rendering decision.

The two tabs do not offer the same things, because the platforms do not have
the same settings. Codex runs every subagent on the model of the session that
spawned it, so the Codex tab has **no per-agent model picker** — only
reasoning effort, which really is per-agent — and no effort row for the
manager, which is the top-level session and has no subagent config at all.

It exists because several settings live in more than one file. Model and
effort must match in `orchestration.json`, the agent's frontmatter (or
`.toml`) **and** the README config table; the test-write flag fans out to
three JSON keys plus the validator's `tools:` allowlist. The UI writes every
copy, then re-runs `verify-install.py` and shows the result, so a change that
breaks the install says so on the spot rather than at your next
`/orchestrate`.

Three values are shown but not editable, for two different reasons.
`schemaVersion` is not a setting — it says which layout the file is parsed
against. `allowBypassPermissions` and `allowDestructiveGit` are the harness
guardrails the whole design rests on: delegates are held back by the
permission system rather than by their prompts, so switching those off is a
deliberate hand edit, not one click in a browser tab. `verify-install.py`
pins all three, and keeps failing the install if one is changed by hand.

Everything else is bounded rather than pinned. Parallel workers (1–8),
correction cycles (0–5), agent retries (0–3), the default-global-agent flag
and both memory flags are ordinary settings; the verifier checks they are
sane, not that they still match what shipped, and the UI offers exactly the
range the verifier accepts.

Requires python3, which the bundle otherwise doesn't; no install step and no
dependencies. It binds loopback only and every request carries a one-run
token, so another page in your browser cannot reach it.

### Upgrading a config from an older bundle

`orchestration.json` is kept across upgrades on purpose, so a bundle that
changes the schema leaves your file behind. Neither installer can parse JSON,
so the migration lives with the verifier:

```bash
python3 ~/.claude/orchestrator-spec/verify-install.py --migrate ~/.claude
```

`/orchestrate-sync` runs it, and the config UI offers it when it sees an old
file. It is a no-op when the schema already matches. Both older schemas
migrate: **2 → 3** added `workflow.researchPolicy`, `judgePolicy` and
`validationPolicy` (`never` / `auto` / `always`), derived from the booleans
they replace; **1 → 3** additionally drops two descriptive blocks nothing
reads any more and backfills the bounded-execution keys (`agentTimeoutSeconds`,
`waitSliceSeconds`, `maximumAgentRetries`). Either way a migrated install
behaves exactly as before until you pick a profile.

### Uninstalling

```bash
./install.sh --uninstall
```

```powershell
.\install.ps1 -Uninstall
```

Same two questions — platform and scope — then it lists every path it is
about to delete and asks once before deleting anything.

It removes only what the bundle installed: the five agent files, the
`orchestrate` and `orchestrate-sync` skills, `orchestrator-spec/`,
`README-orchestration.md` and `orchestration.json`. Your own agents and
skills in the same directories are left alone, and `agents/` or `skills/`
is only removed if uninstalling emptied it. `~/.codex/config.toml` is not
touched — other agents may depend on its `[agents]` table.

Everything else ships as a working default. **Test-file writes and
build/serve commands are OFF**, because widening a permission is a
deliberate decision, not a question to answer while skimming an
installer. Turn them on the same way you change anything else after
install — run `/orchestrate-sync`, which flips the flag in
`orchestration.json` and the validator's tool allowlist together, so the
two can't disagree. For scripted installs, `ORCH_ALLOW_TEST_WRITES=y`
and `ORCH_ALLOW_BUILD_SERVE=y` still set them up front.

The installer does **not** ask about models or effort either. Those ship as
working defaults — manager opus/high, researcher haiku/medium, worker
sonnet/medium, validator haiku/medium, judge sonnet/high — and
`/orchestrate-sync` owns them from there. It *verifies* them on every
run (the shipped `orchestrator-spec/verify-install.py` checks that the
agent frontmatter, `orchestration.json` and the README table all agree)
and raises the question with you only when something actually moved: a
disagreement, a model that no longer exists on your account, or a better
tier appearing. Run `/orchestrate-sync models` to change them
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
/orchestrate-sync
```

This bundle ships with **no assumptions** about what's installed on your
machine — no plugins, no MCP servers, no failed/disabled capabilities are
pre-baked in, and every Codex subagent ships with an empty `mcp_servers`
map (table). `/orchestrate-sync` inspects *your* live installation once and
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
install.sh / install.ps1   — installers, and --uninstall / -Uninstall
tests/                     — smoke suites (bash + PowerShell) and the
                              config-UI test; they install into a
                              throwaway directory and verify the result
templates/
  orchestrator-spec/       — shared spec source (edit + regenerate),
                              platform-neutral, used by both generators
    verify-install.py      — the install's invariants, as code
    config-ui.py           — the browser settings UI
  agents/                  — the 5 Claude Code agent definitions
  skills/                  — Claude Code /orchestrate and /orchestrate-sync
  README-orchestration.template.md   — Claude Code doc template
  codex/
    agents/                — 4 Codex subagent .toml configs + the
                              manager's task-orchestrator.md (read as
                              prose, not a registered subagent)
    skills/                — Codex /orchestrate and /orchestrate-sync
                              (the latter's long procedure lives in
                              references/orchestrate-sync-body.md)
    README-orchestration.template.md   — Codex CLI doc template
```

## Updating an existing install

Re-run the installer (it will ask before overwriting), or edit the
installed `orchestrator-spec/` directly and ask your session to
regenerate per its `generation-plan.md`. Run `/orchestrate-sync`
periodically to keep the capability deny-list and tool/MCP routing in
sync with your installation as it changes.

## Issues and contributions

Bug reports and pull requests: https://github.com/milad-hub/orchestrate-agents/issues.

A change to shared behavior belongs in `templates/orchestrator-spec/`
first, then in both platform templates — `generation-plan.md` explains
how the two are reconciled. Run both smoke suites before opening a PR:

```bash
bash tests/smoke-test.sh
```

```powershell
.\tests\smoke-test.ps1
```

## License

MIT — see [LICENSE](LICENSE).
