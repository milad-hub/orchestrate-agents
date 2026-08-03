# Project Analysis

At run start the manager builds a compact picture of the repository:

1. **Structure**: top-level layout, workspaces/monorepo boundaries
   (nx/turbo/pnpm workspaces), main source roots, test roots.
2. **Git state**: current branch, default branch, dirty files, recent
   commits. Uncommitted user work must be preserved — never reset,
   checkout-over, or stash user changes without explicit approval.
3. **Build system & package manager**: from lockfiles and configs
   (package-lock/pnpm-lock/yarn.lock, angular.json, nx.json, …).
4. **Test frameworks**: jest/vitest/karma/playwright/cypress configs.
5. **CI**: pipelines files, to learn the project's canonical
   build/test/lint commands.
6. **Repository memory**: if codebase-memory MCP has an index for the repo,
   use it for architecture queries (reads only) — but verify memory-derived
   claims against current code before acting on them.
7. **Instruction hierarchy**: per instructions/instruction-file-discovery.md.

Output: internal project profile used for task classification, scope
splitting (disjoint worker scopes), command routing, and — since the
knowledge layer — deciding which technology-scoped documents apply.

## The profile

One object, derived once per run, holding what the rest of the run asks the
repository about. Every field is optional: an undeterminable field is
recorded as unknown and **never** defaulted to a plausible value. A guessed
framework selects the wrong rules, and nothing downstream can tell a guess
from a finding.

| Field | Derived from |
|---|---|
| `languages` | File extensions in the source roots, weighted by count; the languages CI actually builds |
| `frameworks` | Manifest dependencies and framework config files (angular.json, next.config, pom.xml, *.csproj, …) |
| `packages` | Workspace definitions and per-package manifests |
| `modules` | Source roots and their entry points |
| `layers` | Directory naming that the repository itself uses consistently (api/domain/infrastructure, feature/shared) — reported only when the pattern holds, never imposed |
| `folderStructure` | Top-level layout and depth, test roots, generated/vendored directories to leave alone |
| `dependencyGraph` | Workspace-to-workspace edges from the lockfile and manifests. Package-level, not symbol-level: a symbol graph is what the repository-memory MCP is for, and duplicating it here would be a parser this bundle refuses to own |
| `buildTools` | Lockfiles, task runners, build config |
| `ci` | Pipeline definitions, and the canonical commands they run |
| `testFrameworks` | Test configs and test-script targets |
| `lintRules` | Formatter and analyzer configuration (.editorconfig, eslint, ruff, StyleCop, Directory.Build.props) |
| `conventions` | Observed, not asserted: naming, file layout and import style that hold consistently across the sampled source. Reported with the evidence they came from |

Derivation reads what the repository already states about itself. Nothing
here parses source code that another tool already understands better: where
a repository-memory index exists, query it and record that the field came
from there.

`conventions` is the field most able to mislead. A pattern observed in six
files is a pattern; a pattern observed in one is a coincidence. Record the
sample size, and omit the field rather than reporting a weak signal as a
convention.

## Persistence

The profile is written to `.orchestrate/project-profile.json` in the target
repository, so a second run on an unchanged repository reuses it instead of
re-deriving it.

- **Write permission is required.** Writing is a repository mutation like any
  other: when repository writes are not permitted, or the path is not
  writable, the profile is derived in memory and the run continues normally.
  A read-only run is a degraded profile, never a failed run.
- **`.orchestrate/` is not committed by the bundle.** It is derived state
  about one machine's view of the repository. Adding it to `.gitignore` is
  the user's decision, and the manager says so once rather than editing
  ignore files on its own.
- The file records `derivedAt`, the head commit it was derived from, and the
  provenance of each field.

## Staleness

A derived fact is accurate when fresh and misleading when stale — this is the
most dangerous artifact in the run, because it looks like evidence.

A stored profile is **revalidated, never trusted**:

- Re-derive when the head commit differs, when any manifest, lockfile, CI or
  analyzer configuration has changed since `derivedAt`, or when the working
  tree is dirty in a way that touches those files.
- Re-derive when the stored profile was written by a different bundle version.
- A profile that cannot be revalidated is recomputed, not used.
- Fields whose provenance was the repository-memory index are revalidated
  against current code before being acted on, exactly as memory-derived
  claims always are.

Cheap-to-check first: comparing a commit hash and a handful of mtimes is what
makes reuse worth having. If revalidation would cost as much as deriving,
derive.

## Use

- Applicability matching for knowledge documents: the profile supplies the
  tokens a document's `applies` field is matched against
  (knowledge/README.md).
- Task classification and scope splitting.
- Command routing: which build, test and lint commands are the project's own.

Keep it internal; summarize only what the user needs. Report the profile's
provenance when it decided something visible — which technology rules applied
and why is exactly the kind of decision nobody can correct if they cannot see
it.
