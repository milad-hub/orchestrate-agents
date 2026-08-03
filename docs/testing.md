# Testing

**Harness:** [tests/](../tests/) —
[smoke-test.sh](../tests/smoke-test.sh) / [smoke-test.ps1](../tests/smoke-test.ps1),
[verify-install-negative.py](../tests/verify-install-negative.py),
[check-drift.py](../tests/check-drift.py),
[config-ui-test.py](../tests/config-ui-test.py),
[proposal-gate-test.py](../tests/proposal-gate-test.py)

There is nothing to unit-test in the usual sense: the product is markdown, JSON
and TOML. So the harness tests the *install* — it builds real ones into a
throwaway directory and asserts properties of the result.

## What each layer proves

**Smoke suites** — install on each platform and each option combination, then
check what only a fresh install can: the shipped default values, the rendered
models, no leftover `{{TOKENS}}`, no Claude-specific names in the Codex tree,
uninstall removing the bundle and nothing else, bootstrap installing without a
clone.

Two suites because bash and PowerShell installers are separate implementations.
One passing says nothing about the other.

**verify-install.py** — the standing invariants, as code. Run by the smoke
suites, by `/orchestrate-sync`, and by the config UI after every write. It is
the definition of a valid install, not a description of one.

**verify-install-negative.py** — corrupts one thing at a time and asserts the
verifier reacts. Without it, a green verify only means the verifier did not
complain; this is what shows it *would*.

Half its cases assert the verifier stays **quiet**: a prompt-hash check that
fired on a legitimate frontmatter edit would make `/orchestrate-sync` unusable,
which is worse than the drift it prevents.

**check-drift.py** — compares the platform trees structurally: heading layout,
numbered-step counts, status vocabulary derived from `policies/reporting.md`.
Also checks that documentation names spec files that exist.

Structural, not phrase-matching: it catches a section added to one tree and not
the other, which is the realistic failure. It cannot see a rule both trees drop
together — `INVARIANTS` is the small hand-maintained net for the few cases
expensive enough to warrant one.

**config-ui-test.py** — the UI writes several files per setting, so every case
changes a value and re-runs the verifier. It also holds two properties that are
easy to lose: no profile may widen a permission, and every editable setting must
be named by a prompt.

That second one earns its keep. It caught `knowledge.allowProposals` shipping as
a control no prompt read — a switch that changed nothing.

**proposal-gate-test.py** — the learning loop is the one place an agent may
author knowledge, so it is the one place a bad rule could install itself. Three
things hold it shut, asserted from the shipped files: proposals ship off, every
destination is `.orchestrate/proposals/`, and no prompt instructs a merge.

Grep-shaped, because the guarantee is partly an **absence** — and an absence is
what has to be checked.

## What the harness cannot prove

Worth stating plainly, since a green run is easy to over-read:

- **Runtime behavior.** Nothing here runs an agent. That a manager actually
  reuses a stored profile, truncates at the budget, or honors the packet
  slicing table is enforced by prompt contract and checked by the
  mandatory-block guard — not observed. The slicing table is the one case with
  a partial check: the verifier proves the table names real documents and never
  narrows away a security-band one, but not that the manager follows it.
- **Semantic conflicts.** Two rules can each be valid and jointly incoherent.
  The verifier checks structure; the human approval gate on proposals is the
  backstop, and it depends on people reading them.
- **Whether a rule is good.** Only that it is well-formed, findable and
  reachable.

## Running it

```bash
bash tests/smoke-test.sh
```

```powershell
.\tests\smoke-test.ps1
```

Both, before opening a PR. The others run inside them.
