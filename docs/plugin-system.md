# Plugin system

**Spec:** [knowledge/](../templates/orchestrator-spec/knowledge/),
[generation-plan.md](../templates/orchestrator-spec/generation-plan.md),
[agents/](../templates/orchestrator-spec/agents/)

There is no plugin loader, because there is no runtime to load into. Everything
extensible here is extensible the same way: **drop a descriptor in, regenerate
the manifest, change no core file.**

## The eight extension points

| Point | Where | Shape |
|---|---|---|
| Agents | `agents/*.spec.md` + a platform tree | Role spec with a declared-capabilities block |
| Rules | `knowledge/rules/` | Knowledge document, `category: rule` |
| Skills | `knowledge/skills/` | Knowledge document, eight mandatory sections |
| Knowledge providers | `knowledge/providers/` | Descriptor with source, trust level, refresh rule |
| Validators | `verify-install.py` check functions | A function that appends to `FAILURES` |
| Workflow steps | `policies/` | Policy document the manager procedure names |
| Context builders | `knowledge.rankingPolicy` | Named policy honoring the ranking contract |
| Repository analyzers | `discovery/project-analysis.md` fields | A profile field with a stated derivation |

## What the object-oriented words map to

The brief that produced this system asked for dependency injection, interfaces
and composition. In a bundle with no classes those are still real properties,
and each has a concrete form:

- **Dependency injection** → manifest-driven selection. Agents depend on
  `knowledge/index.json`, not on file paths. Swapping a provider or a ranking
  policy changes what the manifest yields, not what any agent says.
- **Interfaces** → descriptor schemas. The five frontmatter fields, the eight
  skill sections, the provider's source/trust/refresh triple. Closed, so a
  violation is detectable rather than silently ignored.
- **Composition** → the assembly order in
  [context-builder.md](context-builder.md). Context is built by combining
  descriptors in a documented order; nothing inherits another document's
  content by transclusion, which would make the result uninspectable.

## Why no core edit is required

Because nothing enumerates the extensions. The manifest is generated from the
tree, and selection is by category and applicability rather than by name.

The exception is deliberate: **role specs are enumerated**, in `ROLES` and
`MANDATORY_BLOCKS` inside the verifier. Adding a sixth agent is a core change on
purpose — a role is a permission boundary, and permission boundaries should not
be addable by dropping in a file.

## What holds it

`verify-install.py` fails an install where a descriptor is malformed, a
declaration disagrees with the harness, or the manifest no longer matches the
tree. A negative test proves each rejection fires — see
[testing.md](testing.md).

Without that, "just drop a file in" means an unnoticed typo is a rule that
silently stopped applying.
