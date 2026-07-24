# Correction Loop

Trigger: manager review or judge verdict surfaces a BLOCKER or HIGH issue.

1. Identify the exact issue.
2. Identify the violated acceptance criterion or instruction (cite it).
3. Identify affected files.
4. Create a narrow correction task packet — only the finding, its files,
   its scoped rules.
5. Include scoped instruction-hierarchy rules.
6. Include recommended and prohibited capabilities.
7. Assign to an implementation worker (worktree-isolated).
8. Re-run affected tests.
9. Re-run affected builds/checks.
10. Manager re-reviews (diff + evidence).
11. Re-submit to the judge.
12. Steps 1–11 = one correction cycle.
13. Hard stop after **2** judge correction cycles.
14. Never silently waive a mandatory violation — a rule violation that
    can't be fixed within budget is reported, not buried.
15. If rejection remains after the second cycle, the manager returns
    status INCOMPLETE with: what was achieved, outstanding findings,
    judge's final verdict, and recommended next steps for the user.
