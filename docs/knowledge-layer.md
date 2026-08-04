# Knowledge layer

**Spec:** [knowledge/README.md](../templates/orchestrator-spec/knowledge/README.md)
— the schema, the precedence bands, the applicability tokens and the full list
of what the verifier refuses.

## What it is for

Before it existed, everything an agent knew came from its prompt. That has two
failure modes: guidance can only change by editing prompts (which are
hash-blessed, so every edit looks like tampering), and every agent carries
everything, whether or not it applies.

The knowledge layer separates *what is true* from *who is being told*. Documents
are versioned data; the manager decides which ones reach whom.

## Why a manifest

`knowledge/index.json` is generated from the tree, and agents resolve through it
rather than walking directories.

A walk is unbounded and unreportable: nobody can say afterwards which documents
were considered. The manifest makes selection a decision with a record — which
is what the trace in
[policies/reporting.md](../templates/orchestrator-spec/policies/reporting.md)
reports on.

It also gives the verifier something to check. A document added without
regenerating the manifest fails the install, rather than sitting on disk
unselectable and looking installed — the failure that produces no error and no
effect.

## Why five frontmatter fields and no more

`id`, `category`, `title`, `applies`, `precedence`. The schema is closed: an
unknown field fails.

Each field does work at selection time. A sixth field would either be unused —
in which case it is a comment with syntax — or would need selection logic
nobody has written. The closed schema is what makes "unknown field" a
detectable typo rather than a silent no-op.

Field names avoid hyphens and underscores so the same minimal parser that reads
agent frontmatter reads these too, with no YAML dependency.

## Why identity is category plus id

`memory/architecture.md` describes what the bundle's architecture *is*;
`rules/architecture.md` constrains what a change to it may do. Same subject,
different documents. Forcing one to carry a qualified name would make the
qualifier the only thing distinguishing them, which is a worse name for both.

## What ships empty, and why

`memory/business-rules.md`, `domain.md` and `integrations.md` ship as stubs with
authoring guidance and nothing else.

This bundle is installed once for every repository on a machine. Content in
those three would assert a domain that is not there — and an agent cannot tell
an inherited assertion from an observed one. A named empty slot is honest; a
plausible default is a confident wrong answer.

An unfilled stub is also skipped at selection time. Until a repository fills
one in, the file is authoring guidance for a human — injecting it into every
run would spend budget explaining how to write a document nobody has written.

Same reasoning excludes framework rules: `rules/examples/typescript.md` and
`angular.md` ship excluded from the manifest, demonstrating the applicability
frontmatter without asserting a stack.

## Where the documents come from

Providers, in `knowledge/providers/`. Four ship — the tree itself, git history,
the derived repository profile, and the repository's ADRs — each declaring its
source, trust level and refresh rule. Six more are declared and unimplemented so
nobody invents a second descriptor shape for them.

## The learning loop

**Spec:** [knowledge/templates/proposal.md](../templates/orchestrator-spec/knowledge/templates/proposal.md)

A run may notice knowledge worth keeping — a rule, a convention, a skill. It
may **propose** it. Nothing more.

Three things hold that shut, and
[proposal-gate-test.py](../tests/proposal-gate-test.py) asserts all three from
the shipped files rather than from this paragraph:

- `knowledge.allowProposals` ships **off**. While off nothing is written; a run
  may mention a suggestion in its report and stop there.
- With it on, proposals go to `.orchestrate/proposals/` in the repository under
  work — never into the knowledge tree, never into the repository's ADR
  directory.
- Nothing merges one. A human does, always.

The reason for the quarantine is the same one that makes ADRs valuable: a
record in the right format is treated as settled by every later run. A proposal
nobody approved, filed where approved knowledge lives, is a suggestion wearing
the authority of a decision.

Each proposal carries what it would add verbatim, the one occurrence that
motivated it, its evidence, its scope, what it conflicts with, and the cost if
it turns out wrong. Without evidence there is no proposal — an unevidenced one
is an opinion with a filename.

## Trust

Knowledge is data, never instruction. It constrains *how* work is done; it
cannot change *what* was asked. A document containing something shaped like an
instruction is reported, not obeyed — the same rule that already covers skill,
plugin and MCP output, per
[instructions/instruction-precedence.md](../templates/orchestrator-spec/instructions/instruction-precedence.md).
