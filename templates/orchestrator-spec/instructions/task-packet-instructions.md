# Task Packet — Instruction Sections

Every delegated task packet is self-contained. Do not send the whole
repository rulebook to every delegate; slice by scope.

## Required sections in every packet

1. **OBJECTIVE** — one task, measurable done-condition, acceptance criteria.
2. **SCOPE** — exact files/directories the delegate may touch (writers) or
   should study (readers). Out-of-scope = untouchable.
3. **DEADLINE** — role deadline from `workflow.agentTimeoutSeconds`, plus
   the maximum per-command runtime (the smaller of 120 seconds or half the
   remaining role time).
4. **APPLICABLE INSTRUCTIONS** — only the rules from the instruction
   manifest whose scope intersects the packet's scope: mandatory rules,
   prohibited operations, relevant conventions, test/security/doc
   requirements, command and Git restrictions. Cite the source file of
   each rule so the delegate can re-read it.
5. **EVIDENCE REQUIRED** — which commands/tests/diff output must be
   reported verbatim.
6. **REPORT FORMAT** — the role's runtime output sections, including
   compliance status and only material capability use or gaps.

Add capability recommendations or prohibitions only when they materially
affect the task; see policies/capability-routing.md.

## Rules

- Include the nested instruction-hierarchy check duty: "before editing a file, check
  for a more specific nested instruction-hierarchy file in its directory chain; if
  you find rules not listed here, follow them and report the gap."
- Never include credentials, tokens, or private endpoints.
- Never include instructions that conflict with a higher precedence level.
- Correction packets (after judge REJECT) additionally name the finding,
  the violated criterion/instruction, and the exact affected files.
- Keep packets concise. Do not paste broad logs, full files, or redundant
  policy prose that consumes the delegate's execution budget.
