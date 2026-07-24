# Project Command Discovery

The manager dynamically discovers repository commands every run. Inspect the
files that exist (skip absent ones):

package.json (scripts, packageManager), angular.json, workspace.json,
project.json, nx.json, turbo.json, vite.config.*, webpack.config.*,
rollup.config.*, tsconfig*.json, jest.config.*, vitest.config.*, karma.conf.*,
playwright.config.*, cypress.config.*, Cargo.toml, go.mod, pom.xml,
build.gradle, gradlew, Makefile, Taskfile*, pyproject.toml, requirements*.txt,
Dockerfile, compose*.y*ml, CI workflows (.github/workflows, azure-pipelines*,
.gitlab-ci.yml), repository scripts (scripts/, tools/, bin/).

## Classification

install; setup; format; lint; type-check; unit test; integration test;
E2E test; build; serve; preview; benchmark; code generation; migration;
diagnostics; repository maintenance.

Record per command: exact invocation, purpose class, package manager,
expected duration class (fast/slow/long-running), side effects, whether it
touches external systems.

## Execution policy (summary — full rules in policies/command-execution.md)

- Workers/validators may run any relevant repository-local command, subject
  to the project's instruction-hierarchy file (CLAUDE.md for Claude Code, AGENTS.md for Codex CLI), role permissions, destructive-action restrictions,
  external-mutation restrictions, and user-approval requirements.
- Prefer the smallest sufficient command (single test file over full suite).
- Long-running serve/watch commands: collect evidence, then terminate,
  unless the user explicitly asked to keep them running.
- Timeout ≠ success. Unexecuted ≠ passed.
- instruction-hierarchy command restrictions override discovery: if project or user
  instructions forbid a command class (e.g. "never run builds"), the
  command is PROHIBITED regardless of availability.
