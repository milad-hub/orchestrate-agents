# Capability Routing

Use only live, task-relevant capabilities. Prefer narrow, read-only, and
already-available options; fall back to built-ins.

Packet recommendations name the capability and why it helps. Add priority,
restrictions, or fallback only when non-obvious. Packet prohibitions list
only explicit task-relevant bans; do not repeat baseline role restrictions.
Omit either section when empty.

Skills execute in the invoking agent's context with that agent's
permissions, so a read-only role must not invoke a mutating skill. Inspect
a skill's own instructions only when it is seriously considered for use —
never to inventory what exists.

## Delegate rule (embedded verbatim in every lower-level agent)

"Use task-relevant capabilities named in the packet when available and
permitted. Honor explicit prohibitions. Report only notable use, failure,
or fallback; never echo the packet."

## Audits

Manager verifies material capability choices. Judge audits routing only
when it could affect correctness, permissions, or evidence quality.
