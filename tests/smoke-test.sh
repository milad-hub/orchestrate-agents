#!/usr/bin/env bash
# Smoke-test matrix for install.sh. Never touches the real ~/.claude or
# ~/.codex -- everything runs against a scratch directory. Run from the
# repo root or anywhere: ./tests/smoke-test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$REPO_ROOT/install.sh"
SCRATCH="$(mktemp -d)"
FAILURES=0
PY="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
if [ -z "$PY" ]; then echo "FAIL: no python/python3 on PATH -- JSON/TOML checks cannot run"; exit 1; fi

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILURES=$((FAILURES + 1)); }

cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

check_no_tokens() {
  local dir="$1" label="$2"
  if grep -rl -F -- '{{' "$dir" >/dev/null 2>&1; then
    fail "$label: leftover {{ tokens found"
  else
    pass "$label: no leftover tokens"
  fi
}

check_no_mcp_leak() {
  local dir="$1" label="$2"
  if [ -d "$dir/agents" ] && grep -rl "mcp__" "$dir/agents" >/dev/null 2>&1; then
    fail "$label: mcp__ (Claude-specific) names leaked into Codex agents"
  else
    pass "$label: no mcp__ leakage"
  fi
}

check_json() {
  local file="$1" label="$2"
  "$PY" - "$file" <<'PYEOF' 2>/tmp/smoke_json_err
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d["capabilities"]["explicitDeny"] == []
assert d["defaultGlobalAgent"] == False
assert d["workflow"]["maximumParallelWorkers"] == 4
assert d["workflow"]["maximumCorrectionCycles"] == 2
assert d["workflow"]["maximumAgentRetries"] == 0
assert d["workflow"]["waitSliceSeconds"] == 60
ts = d["workflow"]["agentTimeoutSeconds"]
assert ts["codebaseResearcher"] == 180 and ts["implementationWorker"] == 600
assert ts["testValidator"] == 300 and ts["resultJudge"] == 180 and ts["correctionWorker"] == 300
assert d["workflow"]["requireIndependentJudge"] == False
assert d["permissions"]["allowBypassPermissions"] == False
assert "followInstructionHierarchy" in d["instructionGovernance"]
assert "inspectNestedInstructionFiles" in d["instructionGovernance"]
assert "followClaudeMdHierarchy" not in d["instructionGovernance"]
PYEOF
  if [ $? -eq 0 ]; then
    pass "$label: orchestration.json valid + invariants hold"
  else
    fail "$label: orchestration.json check failed: $(cat /tmp/smoke_json_err)"
  fi
}

check_toml() {
  local dir="$1" label="$2"
  "$PY" - "$dir" <<'PYEOF' 2>/tmp/smoke_toml_err
import sys, glob
try:
    import tomllib
except ImportError:
    print("tomllib unavailable (py<3.11) -- skipping strict parse", file=sys.stderr)
    sys.exit(0)
d = sys.argv[1]
expect_sandbox = {
    "codebase-researcher.toml": "read-only",
    "result-judge.toml": "read-only",
    "implementation-worker.toml": "workspace-write",
    "test-validator.toml": "workspace-write",
}
for f in glob.glob(d + "/agents/*.toml"):
    data = open(f, "rb").read()
    parsed = tomllib.loads(data.decode("utf-8"))
    name = f.split("/")[-1].split("\\")[-1]
    assert "name" in parsed and "description" in parsed and "developer_instructions" in parsed
    assert parsed.get("sandbox_mode") == expect_sandbox[name], (name, parsed.get("sandbox_mode"))
    assert parsed.get("mcp_servers") == {}, name
PYEOF
  if [ $? -eq 0 ]; then
    pass "$label: all .toml files parse + sandbox_mode correct"
  else
    fail "$label: TOML check failed: $(cat /tmp/smoke_toml_err)"
  fi
}

check_manager_no_frontmatter() {
  local file="$1" label="$2"
  if head -c3 "$file" | grep -q '^---'; then
    fail "$label: task-orchestrator.md unexpectedly has frontmatter"
  else
    pass "$label: task-orchestrator.md has no frontmatter (correct, not a registered subagent)"
  fi
}

run_install() {
  local platform="$1" projdir="$2"
  shift 2
  mkdir -p "$projdir"
  ORCH_NONINTERACTIVE=1 ORCH_PLATFORM="$platform" ORCH_SCOPE=project \
    ORCH_PROJECT_DIR="$projdir" "$@" bash "$INSTALL" >/tmp/smoke_install_out 2>&1
  return $?
}

echo "=== 1/6: claude-only ==="
PROJ="$SCRATCH/claude-only"
if run_install claude "$PROJ"; then
  pass "claude-only: install.sh exited 0"
  check_no_tokens "$PROJ/.claude" "claude-only"
  check_json "$PROJ/.claude/orchestration.json" "claude-only"
else
  fail "claude-only: install.sh failed: $(cat /tmp/smoke_install_out)"
fi

echo "=== 2/6: codex-only ==="
PROJ="$SCRATCH/codex-only"
if ORCH_CODEX_CONFIG_PATH_OVERRIDE="$PROJ/.codex/config.toml" run_install codex "$PROJ"; then
  pass "codex-only: install.sh exited 0"
  check_no_tokens "$PROJ/.codex" "codex-only"
  check_no_mcp_leak "$PROJ/.codex" "codex-only"
  check_json "$PROJ/.codex/orchestration.json" "codex-only"
  check_toml "$PROJ/.codex" "codex-only"
  check_manager_no_frontmatter "$PROJ/.codex/agents/task-orchestrator.md" "codex-only"
  if [ -f "$PROJ/.codex/agents/task-orchestrator.toml" ]; then
    fail "codex-only: task-orchestrator.toml should not exist (manager is top-level session)"
  else
    pass "codex-only: no task-orchestrator.toml (correct)"
  fi
else
  fail "codex-only: install.sh failed: $(cat /tmp/smoke_install_out)"
fi

echo "=== 3/6: both ==="
PROJ="$SCRATCH/both"
if ORCH_CODEX_CONFIG_PATH_OVERRIDE="$PROJ/.codex/config.toml" run_install both "$PROJ"; then
  pass "both: install.sh exited 0"
  check_no_tokens "$PROJ/.claude" "both/claude"
  check_no_tokens "$PROJ/.codex" "both/codex"
  check_no_mcp_leak "$PROJ/.codex" "both/codex"
else
  fail "both: install.sh failed: $(cat /tmp/smoke_install_out)"
fi

echo "=== 4/6: config.toml -- absent (created) ==="
CFG="$SCRATCH/cfg-absent/config.toml"
PROJ="$SCRATCH/cfg-absent-proj"
if ORCH_CODEX_CONFIG_PATH_OVERRIDE="$CFG" run_install codex "$PROJ"; then
  if [ -f "$CFG" ] && grep -q '^\[agents\]' "$CFG"; then
    pass "config.toml absent-case: created with [agents]"
  else
    fail "config.toml absent-case: not created correctly"
  fi
else
  fail "config.toml absent-case: install failed"
fi

echo "=== 5/6: config.toml -- present, no [agents] (appended) ==="
CFG="$SCRATCH/cfg-noagents/config.toml"
mkdir -p "$(dirname "$CFG")"
printf '[other]\nfoo = "bar"\n' > "$CFG"
PROJ="$SCRATCH/cfg-noagents-proj"
if ORCH_CODEX_CONFIG_PATH_OVERRIDE="$CFG" run_install codex "$PROJ"; then
  if grep -q 'foo = "bar"' "$CFG" && grep -q '^\[agents\]' "$CFG"; then
    pass "config.toml no-agents-case: appended, original content preserved"
  else
    fail "config.toml no-agents-case: original content lost or [agents] missing"
  fi
else
  fail "config.toml no-agents-case: install failed"
fi

echo "=== 6/6: config.toml -- present, has [agents] (untouched, warned) ==="
CFG="$SCRATCH/cfg-hasagents/config.toml"
mkdir -p "$(dirname "$CFG")"
printf '[agents]\nmax_concurrent_threads_per_session = 8\n' > "$CFG"
BEFORE_HASH="$(sha256sum "$CFG" | cut -d' ' -f1)"
PROJ="$SCRATCH/cfg-hasagents-proj"
if ORCH_CODEX_CONFIG_PATH_OVERRIDE="$CFG" run_install codex "$PROJ"; then
  AFTER_HASH="$(sha256sum "$CFG" | cut -d' ' -f1)"
  if [ "$BEFORE_HASH" = "$AFTER_HASH" ] && grep -q "WARNING" /tmp/smoke_install_out; then
    pass "config.toml has-agents-case: untouched, warning printed"
  else
    fail "config.toml has-agents-case: file was modified or no warning printed"
  fi
else
  fail "config.toml has-agents-case: install failed"
fi

echo ""
echo "================================================"
if [ "$FAILURES" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
  exit 0
else
  echo "$FAILURES CHECK(S) FAILED"
  exit 1
fi
