# Task Packet — Instruction Sections

Every delegated task packet is self-contained. Do not send the whole
repository rulebook to every delegate; slice by scope.

## Required sections in every packet

1. **OBJECTIVE** — one task, measurable done-condition, acceptance criteria.
2. **SCOPE** — exact files/directories the delegate may touch (writers) or
   should study (readers). Out-of-scope = untouchable.
3. **APPLICABLE INSTRUCTIONS** — only the rules from the instruction
   manifest whose scope intersects the packet's scope: mandatory rules,
   prohibited operations, relevant conventions, test/security/doc
   requirements, command and Git restrictions. Cite the source file of
   each rule so the delegate can re-read it.
4. **RECOMMENDED CAPABILITIES** — per policies/capability-routing.md.
5. **PROHIBITED CAPABILITIES** — per policies/capability-routing.md.
6. **EVIDENCE REQUIRED** — which commands/tests/diff output must be
   reported verbatim.
7. **REPORT FORMAT** — the role's required output sections (see agent
   specs), always including CAPABILITY USAGE and compliance status.

## Rules

- Include the nested instruction-hierarchy check duty: "before editing a file, check
  for a more specific nested instruction-hierarchy file in its directory chain; if
  you find rules not listed here, follow them and report the gap."
- Never include credentials, tokens, or private endpoints.
- Never include instructions that conflict with a higher precedence level.
- Correction packets (after judge REJECT) additionally name the finding,
  the violated criterion/instruction, and the exact affected files.
