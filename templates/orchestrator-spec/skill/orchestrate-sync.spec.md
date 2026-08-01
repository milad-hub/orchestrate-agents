# /orchestrate-sync skill spec

Location: `{{AGENT_HOME_DIR}}/skills/orchestrate-sync/SKILL.md` (global user
skill). On Codex the body lives in
`references/orchestrate-sync-body.md` beside it, because the Codex skill
file carries the procedure by reference rather than inline.
Invocation: `/orchestrate-sync` (also "sync orchestrate", "update
orchestrate"). `/orchestrate-sync models` asks about model and effort
deliberately.

## Behavior

Maintenance, not execution: it reconciles what is installed against the
machine it is installed on, and changes nothing that has not drifted.

- Fast path first. `verify-install.py --sync-start` migrates an older
  `orchestration.json`, records the prompt-body hashes on a first run,
  verifies the install, and prints one `NEXT:` line — `FAST-PATH` (stop),
  `STOP` (fix what it listed), or `FULL-PASS` (re-inspect). The verifier
  orders the work so nothing can edit a prompt body before its hash is
  recorded.
- Live, read-only discovery: enabled/disabled plugins, connected vs
  configured-but-failed MCP servers, the session's skill and agent
  listings, and — only when the CLI version moved — which frontmatter
  fields this release supports.
- Targeted edits only: `capabilities.explicitDeny`, the excluded-capability
  and version lines in `README-orchestration.md`, delegate `tools:`
  allowlists, and `generation-plan.md`'s version-support notes.
  Removing a tool from an allowlist is automatic; adding one needs the
  user's agreement. Prompt bodies are never edited — a deliberate prompt
  change is a re-bless (`verify-install.py --bless`), not a silent edit.
- `verify-install.py --sync-finish` re-runs every check and records
  `cliVersion` / `lastCheckedAt` only if they all pass, so a run that ends
  broken cannot leave a state file claiming success.

## Boundaries

Never enables, disables, installs, updates, or repairs a plugin or MCP
server — discovery only, the same boundary as the install. Never touches
`settings.json`, workflow limits, permission policy, memory settings, or
`defaultGlobalAgent`; those are user decisions, so it stops and asks
instead of changing them.

## Frontmatter

`name: orchestrate-sync`, `description` scoped to re-syncing the
installation, and explicitly not to running tasks — that is `/orchestrate`.
