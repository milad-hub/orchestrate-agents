# Capability Routing

The manager matches discovered capabilities to the task and each subtask.

## Ranking criteria (in order)

1. system and policy compliance; 2. instruction-hierarchy compliance; 3. exact
relevance; 4. availability; 5. role permissions; 6. read-only vs mutating
needs; 7. trustworthiness; 8. evidence quality; 9. scope specificity;
10. context efficiency; 11. cost; 12. latency; 13. risk; 14. safe fallback
availability.

Prefer narrow over broad, read-only over mutating, one capability over two
overlapping ones. Fall back to built-in tools when nothing better exists.
Do not force irrelevant capability use.

## RECOMMENDED CAPABILITIES (required packet section)

Per recommendation: exact capability name; type; purpose; expected benefit;
priority (REQUIRED / PREFERRED / OPTIONAL); permitted usage; restrictions;
fallback.

## PROHIBITED CAPABILITIES (required packet section)

Include: disabled capabilities; failed capabilities; explicitly denied
capabilities (`capabilities.explicitDeny`); mutating tools forbidden for the
role; irrelevant external systems; redundant overlapping skills;
capabilities conflicting with the project's instruction-hierarchy file (CLAUDE.md for Claude Code, AGENTS.md for Codex CLI); capabilities outside assigned
scope.

## Delegate rule (embedded verbatim in every lower-level agent)

"Review the RECOMMENDED CAPABILITIES and PROHIBITED CAPABILITIES sections
of the task packet. Use required or preferred capabilities only when
available, relevant, permitted, and compatible with the applicable instruction-hierarchy file
rules. You may decline optional capabilities with a reason. Report exactly
which capabilities you invoked, which you skipped, what outputs they
produced, and which fallbacks you used."

## Delegate behavior

- PREFERRED/OPTIONAL may be declined with a reason.
- REQUIRED unavailable ⇒ use the documented fallback and report the gap.

## CAPABILITY USAGE (required report section from every delegate)

recommended capabilities; capabilities invoked; capabilities skipped;
reasons; fallbacks used; important outputs; failures or ambiguity.

## Audits

Manager reviews every delegate's capability usage against the packet.
Judge audits the routing itself: were relevant capabilities recommended,
irrelevant ones prohibited, prohibitions honored, usage verified.
