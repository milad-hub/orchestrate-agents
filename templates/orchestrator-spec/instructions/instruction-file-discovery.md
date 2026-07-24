# Instruction-File Discovery

Every project has an instruction-hierarchy file the manager must discover
and follow: CLAUDE.md for Claude Code, AGENTS.md for Codex CLI. The
loading mechanics differ by platform — do not assume false parity between
them. This installer never authors or edits either file at any level; the
orchestrator only discovers and reads them.

### Claude Code

- **User-level**: `~/.claude/CLAUDE.md` — loaded for every session.
- **Project**: `CLAUDE.md` at the repository root and in parent directories
  of the working directory (walking up) — loaded at launch.
- **Nested**: `CLAUDE.md` in subdirectories — loaded on demand when files
  in that subtree are read/edited; scope is the containing directory
  subtree.
- **CLAUDE.local.md**: supported (auto-gitignored, per-checkout overrides);
  same scoping as its sibling CLAUDE.md.
- **Imports**: `@path/to/file` syntax inside CLAUDE.md pulls in additional
  files, recursively (bounded hop depth). Imported files inherit the
  importer's precedence level.
- **Managed**: organization-managed policy files, when present, outrank
  user/project instructions.

### Codex CLI

- Resolution order, closer-to-cwd wins on conflict, files concatenated:
  `~/.codex/AGENTS.md` (global default) → `<git-root>/AGENTS.md` (repo
  root, NOT inside `.codex/`) → every intermediate directory's
  `AGENTS.md` → `<cwd>/AGENTS.md`.
- **`.override.md` siblings**: at each level, an `AGENTS.override.md` next
  to `AGENTS.md` beats it — e.g. `<git-root>/AGENTS.override.md` beats
  `<git-root>/AGENTS.md`.
- **Size cap**: total concatenated instruction text is capped at 32 KiB
  (`project_doc_max_bytes`); Codex skips empty files and stops once the
  cap is reached. Do not assume every discovered file's full content
  actually loads into context — budget accordingly.
- No import syntax, no "local" per-checkout variant, no managed-policy
  tier — Codex has none of these; do not invent them.

## Manager procedure (start of every run, both platforms)

1. Enumerate the applicable instruction-hierarchy file at every relevant
   level (user/global, repo-root, intermediate directories, cwd), plus
   any platform-specific override/local variant and imports.
2. Build the instruction manifest. Per source record: source path; scope
   (affected paths); mandatory rules; prohibited operations; coding
   conventions; architecture constraints; test requirements; security
   requirements; documentation requirements; dependency rules;
   generated-file rules; command requirements; tool restrictions; Git
   restrictions; exceptions; conflicts.
3. Keep the manifest internal; slice it per task packet
   (task-packet-instructions.md).

## Subagent caveat

Subagents do not reliably auto-load the instruction hierarchy the way the
top-level session does. Therefore scoped rules MUST travel inside task
packets, and delegates additionally check for a more specific nested
instruction-hierarchy file beside any file they touch.
