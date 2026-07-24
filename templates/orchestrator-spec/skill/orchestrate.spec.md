# /orchestrate skill spec

Location: `{{AGENT_HOME_DIR}}/skills/orchestrate/SKILL.md` (global user skill).
Invocation: `/orchestrate <task>`.

## Behavior

The skill is a thin entry point into the orchestration workflow. It does
NOT duplicate the manager prompt. It instructs the CURRENT SESSION to
adopt the manager role by reading and following
`{{AGENT_HOME_DIR}}/agents/task-orchestrator.md` directly. Rationale: in this
harness subagents cannot spawn agents, so a spawned manager would lose
its researcher/worker/validator/judge pipeline (observed in the first
live run); the main session can spawn agents, so the manager must run
there. The session then executes the manager procedure:

- load `{{AGENT_HOME_DIR}}/orchestration.json`;
- dynamic capability discovery; instruction-hierarchy discovery; project command
  discovery;
- define acceptance criteria; delegate only when useful;
- ≤ 4 parallel lower-level agents; no overlapping edits;
- manager review required; validation required; independent judge
  required; ≤ 2 judge correction cycles;
- one consolidated final report relayed to the user.

## Frontmatter

`name: orchestrate`, `description` scoped to explicit orchestration
requests (multi-agent workflow for substantial tasks) so it does not
auto-trigger on trivial prompts.

## Alternative launch

`claude --agent task-orchestrator` runs the manager as the session's main
agent — identical behavior to the skill path. The orchestrator is never
the default agent.
