# Permission Policy

Policy: **balanced** — normal Claude Code permission prompts stay active;
no agent runs with bypassPermissions, ever (`allowBypassPermissions: false`).

## Per-role envelope

| Capability | Manager | Researcher | Worker | Validator | Judge |
|---|---|---|---|---|---|
| Read repository | yes | yes | yes | yes | yes |
| Write source | yes | no | assigned scope | **no** | no |
| Write tests/fixtures/snapshots | yes | no | packet-gated (default off) | packet-gated (default off) | no |
| Run project commands | yes | safe inspection only | yes (build/serve default off) | yes (build/serve default off) | safe diagnostics only |
| Spawn agents | **yes (only one)** | no | no | no | no |
| Mutating MCP / external systems | approval-gated | no | approval-gated | approval-gated | no |
| Repository-memory reads | yes | yes | yes | yes | yes |
| Repository-memory writes | no | no | no | no | no |

## Enforcement mechanism

- Tool-level: `tools:` allowlists (the generated agents do not rely on
  `disallowedTools`). Researcher and judge get no Edit/Write/NotebookEdit
  and no Agent. The worker gets Edit/Write but not Agent. The validator
  gets Edit/Write only when test writes were enabled at install time —
  with the default off, the allowlist withholds them and the harness, not
  a prompt rule, keeps it read-only.
- **Limitation**: Claude Code cannot natively restrict (a) Bash to
  read-only commands, (b) the validator's writes to test files only when
  test writes are enabled, or (c) worker writes to an assigned scope. These are enforced by strong
  prompt rules, manager review of the diff, and judge audit. Documented in
  README-orchestration.md.
- Destructive Git (reset --hard, push --force, checkout over dirty files,
  clean -f, branch -D, history rewrite) is forbidden for all agents unless
  the user explicitly approves the specific command.
- External mutations (Azure DevOps writes, pushes, publishes, network
  side effects) require explicit user approval routed through the manager
  (policies/external-systems.md).
- Persistent agent memory: disabled — no `memory` frontmatter, no writes
  to `{{AGENT_HOME_DIR}}/projects/*/memory` by orchestration agents.
