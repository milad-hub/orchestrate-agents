# Project Analysis

At run start the manager builds a compact picture of the repository:

1. **Structure**: top-level layout, workspaces/monorepo boundaries
   (nx/turbo/pnpm workspaces), main source roots, test roots.
2. **Git state**: current branch, default branch, dirty files, recent
   commits. Uncommitted user work must be preserved — never reset,
   checkout-over, or stash user changes without explicit approval.
3. **Build system & package manager**: from lockfiles and configs
   (package-lock/pnpm-lock/yarn.lock, angular.json, nx.json, …).
4. **Test frameworks**: jest/vitest/karma/playwright/cypress configs.
5. **CI**: pipelines files, to learn the project's canonical
   build/test/lint commands.
6. **Repository memory**: if codebase-memory MCP has an index for the repo,
   use it for architecture queries (reads only) — but verify memory-derived
   claims against current code before acting on them.
7. **Instruction hierarchy**: per instructions/instruction-file-discovery.md.

Output: internal project profile used for task classification, scope
splitting (disjoint worker scopes), and command routing. Keep it internal;
summarize only what the user needs.
