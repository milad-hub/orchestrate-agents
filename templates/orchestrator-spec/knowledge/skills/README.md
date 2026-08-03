# Skills

Reusable procedures agents invoke by name instead of the manager re-explaining
them in every packet.

Two things separate a skill from prose: it is **named**, so a packet points at
it rather than carrying it, and it **states its own completion criteria**, so
finishing is a check rather than an opinion.

## What ships

| Skill | Ends where |
|---|---|
| `feature-development` | New behavior exists, checkable |
| `bug-fixing` | Cause fixed, regression check in place |
| `debugging` | Cause identified — no fix applied |
| `code-review` | Verdict with ranked findings |
| `testing` | Verdict with classified failures |
| `refactoring` | Structure changed, behavior demonstrably not |
| `documentation` | Verified content, in the document that owns the subject |
| `performance` | Measured improvement, behavior unchanged |
| `security` | Trust boundaries enumerated with verdicts |

`debugging` and `bug-fixing` are deliberately separate: one ends at an
identified cause, the other starts there. Conflating them loses the reviewable
boundary between finding and changing.

## Writing one

Copy `knowledge/templates/skill.md`, keep all eight headings, and regenerate
the manifest. Adding a skill requires no edit to any core spec file — the
descriptor is dropped in and indexed.

Write one only when the procedure recurs. A skill used once is a paragraph that
has been given a filing system.

This README carries no frontmatter and never appears in the manifest.
