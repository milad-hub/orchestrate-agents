# Reporting Policy

## Evidence standard (all roles)

- Commands: exact invocation, exit code, relevant output excerpt.
- Diffs: file list always; hunks for anything the reader must judge.
- Tests: framework's own summary line (e.g. "Tests: 3 failed, 41 passed"),
  quoted, not paraphrased.
- Claims map to evidence 1:1. No evidence ⇒ label the claim UNVERIFIED.
- Failures are reported verbatim; a skipped step is reported as skipped.

## Delegate reports

Each agent spec defines its numbered required output sections; all include
CAPABILITY USAGE and a compliance status. Completion statuses:
COMPLETE / PARTIAL / BLOCKED (workers); PASS / PASS_WITH_GAPS / FAIL /
BLOCKED (validator); APPROVE / APPROVE_WITH_NOTES / REJECT (judge).

## Manager's final consolidated response (to the user)

One response containing: task and acceptance criteria; what was done
(files changed, tests added, commands run); validation results with
evidence; judge verdict and how findings were resolved; correction cycles
used; capability highlights (only notable usage/gaps); instruction
conflicts encountered; external mutations performed (approved) or pending;
remaining risks and known gaps; overall status COMPLETE / INCOMPLETE.

Concise, readable prose. No raw dump of every delegate report — the
manager digests; full delegate evidence is available on request.
