# Memory

**Spec:** [knowledge/memory/](../templates/orchestrator-spec/knowledge/memory/),
[discovery/project-analysis.md](../templates/orchestrator-spec/discovery/project-analysis.md),
[knowledge/providers/](../templates/orchestrator-spec/knowledge/providers/)

"Memory" here means what an agent knows about a project. It comes from three
places with very different trust levels, and keeping them distinct is the whole
point.

## Curated: the memory documents

Eight documents under `knowledge/memory/`. Five carry content about this bundle;
three (`business-rules`, `domain`, `integrations`) ship empty because their
content is per-repository — see [knowledge-layer.md](knowledge-layer.md).

Trust level **curated**: a human wrote them for this purpose. Still data, never
instruction.

## Derived: the repository profile

`.orchestrate/project-profile.json` in the target repository — languages,
frameworks, packages, modules, layers, folder structure, package-level
dependency graph, build tools, CI, test frameworks, lint rules, observed
conventions.

Trust level **derived**, and this is the artifact most able to mislead, because
a guess in it reads exactly like a finding. Three rules follow from that:

- **Unknown is recorded as unknown.** Never defaulted to a plausible value. A
  guessed framework selects the wrong rules and nothing downstream can tell the
  guess from a finding.
- **Reuse requires revalidation.** Same head commit, no manifest, lockfile, CI
  or analyzer change since it was derived, same bundle version. Otherwise
  re-derive. Cheap checks first — if revalidating costs as much as deriving,
  derive.
- **Conventions are observed, not asserted.** A pattern in six files is a
  pattern; a pattern in one is a coincidence. The field is omitted rather than
  reporting a weak signal, and it records its sample size.

Writing the profile is a repository mutation. Without write permission it is
held in memory and the run continues — a read-only run is a degraded profile,
never a failed run. `.orchestrate/` is derived state about one machine's view;
the manager mentions it once rather than editing anyone's `.gitignore`.

## Observed: git history and repository memory indexes

Commit messages, branch names, file history, and a repository-memory MCP index
where one exists.

Trust level **observed**: written by people who were not addressing an agent.
Useful as signal, never as authority. Every memory-derived claim is verified
against current code before being acted on, and a commit message containing
something shaped like a directive is reported rather than obeyed.

## What is deliberately absent

**Persistent agent memory ships off.** `memory.persistentAgentMemory` is false:
delegates start every run cold.

On, an agent carries state between runs — which also means a wrong idea
survives the run that formed it, and nothing in the next run is looking for it.
That trade is available, and it is a decision rather than a default.

**No embedding index.** Selection is applicability and precedence, not
similarity. A vector store is a runtime dependency, and the bundle has none. The
ranking contract in [context-builder.md](context-builder.md) is the seam one
would plug into.
