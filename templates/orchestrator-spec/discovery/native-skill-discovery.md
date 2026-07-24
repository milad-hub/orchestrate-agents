# Native & Bundled Skill Discovery

Source of truth: the session's available-skills listing (system context) —
it already merges native/bundled skills, user skills, project skills, and
plugin skills with one-line descriptions.

Procedure:
1. Read the session skill listing. Record name, source prefix
   (`plugin:skill` form for plugins; path-scoped form for project skills),
   and description.
2. For a skill under serious consideration, read its SKILL.md
   (user: `{{AGENT_HOME_DIR}}/skills/<name>/SKILL.md`; project:
   `.claude/skills/<name>/SKILL.md`; plugin: under
   `{{AGENT_HOME_DIR}}/plugins/marketplaces/...`) before recommending — description
   lines can undersell or oversell.
3. Classify read-only vs mutating from what the skill instructs (a review
   skill that edits files is mutating).
4. Skills execute in the invoking agent's context with its permissions; a
   read-only role must not invoke a mutating skill.

Bundled/built-in skills (e.g. code-review, simplify, loop, schedule) appear
in the same listing; treat identically. Never assume a remembered skill still
exists — the listing of the current session decides.
