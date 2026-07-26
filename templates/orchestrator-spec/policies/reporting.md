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

Concise, readable prose. No raw dump of every delegate report — the
manager digests; full delegate evidence is available on request.
