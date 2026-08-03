# Extending

**Spec:** [generation-plan.md](../templates/orchestrator-spec/generation-plan.md),
[knowledge/README.md](../templates/orchestrator-spec/knowledge/README.md)

Every recipe here ends the same way: run both smoke suites. A change is
finished when both pass, not when one does — they do not test the same paths.

## Add a rule

1. Write `templates/orchestrator-spec/knowledge/rules/<id>.md` with the five
   frontmatter fields. `id` equals the filename stem.
2. Choose `applies`: `*`, or technology tokens matched against the repository
   profile. A token that matches nothing excludes the document rather than
   including it everywhere — a typo is a missing rule, not a wrong one.
3. Choose a precedence band ([rules.md](rules.md)). Above 80 is security only.
4. Regenerate: `python3 templates/orchestrator-spec/verify-install.py
   --index-knowledge templates/orchestrator-spec`
5. Update the document counts in both smoke suites.

## Add a skill

Copy `knowledge/templates/skill.md`, keep all eight headings, regenerate. Write
one only when the procedure recurs.

## Add a knowledge provider

Write a descriptor in `knowledge/providers/` stating source, trust level
(curated / derived / observed), refresh rule, failure behavior and write path.
Read-only unless there is a specific reason otherwise, and a write path that
touches `knowledge/` needs a much better reason than convenience.

## Add a validator check

Add a function to `verify-install.py` that appends to `FAILURES`, call it from
`run_checks` **and** from `main`, and add a case to
`tests/verify-install-negative.py` proving it fires. A check with no negative
case only proves it did not complain.

## Add a configuration setting

The expensive one, because settings fan out:

1. `orchestration.template.json`, and bump `schemaVersion`.
2. A migration in `verify-install.py --migrate`, additive — never overwrite a
   value the user had already tuned.
3. Invariants in `check_json`. Bounded, not pinned, unless it is a permission.
4. A row in `config-ui.py`, plus profile-stop values if it scales with
   thoroughness. Permissions never go on a profile.
5. Name it in a prompt. The config-UI binding test fails a setting no prompt
   reads — an editable control that changes nothing is worse than no control.
6. Document it in both `README-orchestration.template.md` files.
7. Assert the shipped default in both smoke suites.

## Add a platform generator

The conformance checklist. Derived from what the two existing generators
actually differ on, so it is a list of real divergences rather than an
imagined one.

**Files to produce**

- [ ] Five role prompts in the platform's own format. Four delegates plus the
      manager.
- [ ] `orchestrate` and `orchestrate-sync` skills in the platform's format.
- [ ] `README-orchestration.template.md`, including the configuration table —
      `verify-install.py` parses it, so the column order must match.
- [ ] `orchestrator-spec/` copied verbatim, knowledge tree included. Nothing in
      it is platform-specific.

**Divergences to decide, each with a reason**

- [ ] **How writes are granted.** Claude uses a `tools:` allowlist; Codex uses
      `sandbox_mode`. Whatever the platform offers, the verifier's
      `check_registry` must be able to read it, because a role's declared
      writes are checked against what the harness actually grants.
- [ ] **Whether the manager is a registered agent.** On Codex it is prose the
      session reads, not a subagent — which is why the mandatory-block check
      does not cover it there. If the platform can register it, say so.
- [ ] **Per-agent model.** Claude pins one; Codex inherits the session model,
      so its config UI has no model picker. Which is true here?
- [ ] **Waiting on delegates.** Claude delegates push completion; Codex blocks
      on `wait_agent` in slices. `check-drift.py` pins this divergence in
      `INVARIANTS` — add the new platform there.
- [ ] **Concurrency ceiling.** Codex needs
      `max_concurrent_threads_per_session` ≥ the parallel-worker setting, or it
      silently runs fewer agents than the manager scheduled. Does this platform
      have an equivalent trap?
- [ ] **Worktree isolation.** Claude passes `isolation: "worktree"` at spawn;
      Codex isolates natively. Neither is a frontmatter key.

**Wiring**

- [ ] Installer: copy pass, uninstall list, platform prompt.
- [ ] `verify-install.py`: a `check_<platform>` alongside `check_claude` and
      `check_codex`, autodetected the way `agents/*.toml` detects Codex today.
- [ ] `check-drift.py`: add the tree to `AGENT_PAIRS` and `SKILL_PAIRS`.
- [ ] `config-ui.py`: a tab, and `is_codex`-style branches generalized.
- [ ] Both smoke suites: an install case, plus negative cases.

**Validating the checklist**

Walk an existing generator against it. Every box must be answerable from files
that already exist — a box nothing answers is a box that will be guessed at.

## What not to do

- Do not edit a generated tree directly. The next regeneration reverts it
  silently.
- Do not add a rule the verifier cannot check. It lasts until the first person
  who did not read the prose.
- Do not widen a permission as a side effect of anything.
