# Reporting Policy

## Evidence standard (all roles)

- Commands: exact invocation, exit code, relevant output excerpt.
- Diffs: file list always; hunks for anything the reader must judge.
- Tests: framework's own summary line (e.g. "Tests: 3 failed, 41 passed"),
  quoted, not paraphrased.
- Claims map to evidence 1:1. No evidence ⇒ label the claim UNVERIFIED.
- Failures are reported verbatim; a skipped step is reported as skipped.

## Delegate reports

Each runtime agent prompt defines its numbered output sections and carries
compliance in the final status line. Sections are emitted in order only
when they carry content; capability usage appears only when material.
Empty/not-applicable sections are omitted (never "N/A" rows), and command
output is quoted only for failures and the framework's summary line.
Completion statuses, one line per role (canonical — agent prompts must
match, `tests/check-drift.py` derives from here):

- codebase-researcher: COMPLETE / PARTIAL / BLOCKED / TIMEOUT
- implementation-worker: COMPLETE / PARTIAL / BLOCKED / TIMEOUT
- test-validator: PASS / PASS_WITH_GAPS / FAIL / BLOCKED / TIMEOUT
- result-judge: APPROVE / APPROVE_WITH_NOTES / REJECT / INCONCLUSIVE

## Trace

The run says why it believed what it believed. The test of this section is
whether a reader can reconstruct a decision — particularly which knowledge
applied — without re-running anything.

Report the *decisions*, not the mechanics. A trace that lists every file read
is a log; a trace that says which rule won and what it displaced is evidence.
Each stage below is one or two lines, and a stage that did not run says so and
why rather than being omitted — silence reads as "nothing to report", which is
a different claim.

- **Repository analysis** — whether the profile was reused or re-derived, and
  what forced a re-derivation. Fields that came out unknown, since an unknown
  field is what makes a technology rule not apply.
- **Context construction** — what was assembled, in what order, and what the
  budget cut. Say which budget bound first: documents or characters.
- **Knowledge retrieval** — the documents selected, by id. The profile tokens
  that made each technology-scoped one apply. What was dropped for budget.
  When the layer was skipped: disabled, or nothing applicable.
- **Rule selection** — any conflict between two documents, how it resolved,
  and what the resolution displaced. A rule that stopped applying is worth a
  line; a conflict resolved silently is a rule that stopped applying without
  anyone noticing.
- **Skill selection** — the skill invoked, and each of its completion criteria
  as met or not met. A skill whose criteria are not reported against was not
  really invoked.
- **Decision records** — the ADRs that bore on the work, including any the
  change came close to contradicting, and any carrying superseded status.
- **Workflow execution** — delegates dispatched, what each was scoped to,
  parallelism actually used, timeouts and retries, worktree integration.
- **Validation** — commands run with exit codes, the baseline compared
  against, and how each failure was classified.
- **Learning proposals** — any proposal generated, with its path, stated as
  awaiting a human. Never as something that has been applied.

## Manager's final consolidated response (to the user)

One response containing: task and acceptance criteria; what was done
(files changed, tests added, commands run); validation results with
evidence; judge verdict and how findings were resolved; correction cycles
used; capability highlights (only notable usage/gaps); instruction
conflicts encountered; external mutations performed (approved) or pending;
remaining risks and known gaps; overall status COMPLETE / INCOMPLETE.
When no judge was warranted, report the manager compliance-gate result
instead of manufacturing a judge verdict.
List every timed-out delegate, whether it was closed, and whether a retry
or local fallback completed its scope.
Carry the trace above at the depth the task warrants: a trivial run states
which stages it skipped in one line, a complex one reports each stage.

Concise, readable prose. No raw dump of every delegate report — the
manager digests; full delegate evidence is available on request.
