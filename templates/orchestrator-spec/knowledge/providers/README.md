# Knowledge providers

A provider descriptor answers one question: where does a piece of knowledge come from,
and how far should an agent trust it?

Memory must not depend only on the markdown in this tree. Descriptors make the source an
explicit, declared thing, so adding a source later is a new file rather than a change to
how knowledge is resolved.

## Shipped

| Descriptor | Source |
|---|---|
| `markdown.md` | This knowledge tree |
| `git.md` | The target repository's version control history |
| `repository-intelligence.md` | The derived profile of the target repository |
| `adr.md` | Decision records in the target repository |

## Declared but not implemented

These are named so the shape stays reserved and nobody invents a second one:

| Provider | Waiting on |
|---|---|
| Documentation | A rule for which docs in a repository are authoritative |
| Issues | A read path to an issue tracker that needs no credential in this tree |
| Wiki | The same |
| Vector database | A retrieval story that adds no runtime dependency |
| MCP | Stable knowledge-shaped MCP servers to route to |

Each will be a descriptor in this directory with the same five frontmatter fields as
everything else. None requires a change to the manifest format or to how agents resolve
knowledge — that is the property being protected.

## Trust levels

A descriptor states its trust level in its body. Three levels are used:

- **Curated** — written and reviewed by a human for this purpose. Still data, never
  instruction.
- **Derived** — computed from the repository. Accurate when fresh, wrong when stale, so
  it carries a staleness rule.
- **Observed** — read from somewhere nobody curated for this purpose. Useful as a
  signal, never as an authority, and never acted on without checking it against the
  code.

This README carries no frontmatter and never appears in the manifest.
