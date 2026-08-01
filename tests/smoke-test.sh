#!/usr/bin/env bash
# Smoke-test matrix for install.sh. Never touches the real ~/.claude or
# ~/.codex -- everything runs against a scratch directory. Run from the
# repo root or anywhere: ./tests/smoke-test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$REPO_ROOT/install.sh"
SCRATCH="$(mktemp -d)"
FAILURES=0
PY=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 &&
     "$candidate" -c "import sys" >/dev/null 2>&1; then
    PY="$(command -v "$candidate")"
    break
  fi
done
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

# The install's standing invariants live in orchestrator-spec/verify-install.py
# -- one executable list, shared with /orchestrate-sync. What stays here is
# what only a FRESH install can assert: the shipped default values, which the
# user (or /orchestrate-sync) is free to change afterwards.
check_json() {
  local file="$1" label="$2"
  "$PY" - "$file" <<'PYEOF' 2>/tmp/smoke_json_err
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d["capabilities"]["explicitDeny"] == [], "deny list should ship empty"
assert d["workflow"]["waitSliceSeconds"] == 60
ts = d["workflow"]["agentTimeoutSeconds"]
assert ts["codebaseResearcher"] == 180 and ts["implementationWorker"] == 900
assert ts["testValidator"] == 300 and ts["resultJudge"] == 180 and ts["correctionWorker"] == 300
assert d["workflow"]["judgePolicy"] == "auto", "judge policy should ship as auto"
assert d["workflow"]["validationPolicy"] == "auto"
assert d["workflow"]["researchPolicy"] == "auto"
# The booleans these replaced must not ship alongside them: two answers to one
# question, with nothing saying which wins.
for gone in ("requireIndependentJudge", "requireValidation"):
    assert gone not in d["workflow"], "%s still shipped" % gone
# Pruned in schema 2: they were all-true restatements of the prompt prose.
assert "instructionGovernance" not in d
assert "capabilityRouting" not in d
PYEOF
  if [ $? -eq 0 ]; then
    pass "$label: orchestration.json ships the documented defaults"
  else
    fail "$label: orchestration.json check failed: $(cat /tmp/smoke_json_err)"
  fi
}

check_verify() {
  local dir="$1" label="$2"
  if "$PY" "$REPO_ROOT/templates/orchestrator-spec/verify-install.py" "$dir" \
       >/tmp/smoke_verify_out 2>&1; then
    pass "$label: verify-install.py clean"
  else
    fail "$label: verify-install.py: $(cat /tmp/smoke_verify_out)"
  fi
}

# Proves verify-install.py would fail if the install were broken. Without this
# a green verify only means it did not complain.
check_verify_negative() {
  local dir="$1" label="$2"
  if "$PY" "$REPO_ROOT/tests/verify-install-negative.py" "$dir" \
       >/tmp/smoke_verifyneg_out 2>&1; then
    pass "$label: verify-install.py rejects every corrupted variant"
  else
    fail "$label: verify-install negative cases: $(cat /tmp/smoke_verifyneg_out)"
  fi
}

check_worker_model() {
  # The worker authors production code; a weak default is paid back in
  # correction cycles, so pin the rendered default.
  local file="$1" label="$2"
  if grep -q '^model: sonnet' "$file"; then
    pass "$label: worker renders model: sonnet (default)"
  else
    fail "$label: worker model is not sonnet: $(grep -m1 '^model:' "$file")"
  fi
}

check_drift() {
  if "$PY" "$REPO_ROOT/tests/check-drift.py" >/tmp/smoke_drift_out 2>&1; then
    pass "templates: structure and step references valid"
  else
    fail "templates: Claude/Codex drift: $(cat /tmp/smoke_drift_out)"
  fi
}

run_install() {
  local platform="$1" projdir="$2"
  shift 2
  mkdir -p "$projdir"
  env ORCH_NONINTERACTIVE=1 ORCH_PLATFORM="$platform" ORCH_SCOPE=project \
    ORCH_PROJECT_DIR="$projdir" "$@" bash "$INSTALL" >/tmp/smoke_install_out 2>&1
  return $?
}

echo "=== 0/12: template drift (Claude vs Codex) ==="
check_drift

echo "=== 1/12: claude-only ==="
PROJ="$SCRATCH/claude-only"
if run_install claude "$PROJ" ORCH_ALLOW_TEST_WRITES=n; then
  pass "claude-only: install.sh exited 0"
  check_no_tokens "$PROJ/.claude" "claude-only"
  check_json "$PROJ/.claude/orchestration.json" "claude-only"
  check_verify "$PROJ/.claude" "claude-only"
  check_verify_negative "$PROJ/.claude" "claude-only"
  check_worker_model "$PROJ/.claude/agents/implementation-worker.md" "claude-only"
else
  fail "claude-only: install.sh failed: $(cat /tmp/smoke_install_out)"
fi

echo "=== 2/12: codex-only ==="
PROJ="$SCRATCH/codex-only"
if ORCH_CODEX_CONFIG_PATH_OVERRIDE="$PROJ/.codex/config.toml" run_install codex "$PROJ"; then
  pass "codex-only: install.sh exited 0"
  check_no_tokens "$PROJ/.codex" "codex-only"
  check_no_mcp_leak "$PROJ/.codex" "codex-only"
  check_json "$PROJ/.codex/orchestration.json" "codex-only"
  check_verify "$PROJ/.codex" "codex-only"
  check_verify_negative "$PROJ/.codex" "codex-only"
else
  fail "codex-only: install.sh failed: $(cat /tmp/smoke_install_out)"
fi

echo "=== 3/12: both ==="
PROJ="$SCRATCH/both"
if ORCH_CODEX_CONFIG_PATH_OVERRIDE="$PROJ/.codex/config.toml" run_install both "$PROJ"; then
  pass "both: install.sh exited 0"
  check_no_tokens "$PROJ/.claude" "both/claude"
  check_no_tokens "$PROJ/.codex" "both/codex"
  check_no_mcp_leak "$PROJ/.codex" "both/codex"
else
  fail "both: install.sh failed: $(cat /tmp/smoke_install_out)"
fi

echo "=== 4/12: config.toml -- absent (created) ==="
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

echo "=== 5/12: config.toml -- present, no [agents] (appended) ==="
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

echo "=== 6/12: config.toml -- has [agents], value is fine (untouched, quiet) ==="
CFG="$SCRATCH/cfg-hasagents/config.toml"
mkdir -p "$(dirname "$CFG")"
printf '[agents]\nmax_concurrent_threads_per_session = 8\n' > "$CFG"
BEFORE_HASH="$(sha256sum "$CFG" | cut -d' ' -f1)"
PROJ="$SCRATCH/cfg-hasagents-proj"
if ORCH_CODEX_CONFIG_PATH_OVERRIDE="$CFG" run_install codex "$PROJ"; then
  AFTER_HASH="$(sha256sum "$CFG" | cut -d' ' -f1)"
  if [ "$BEFORE_HASH" != "$AFTER_HASH" ]; then
    fail "config.toml has-agents-case: an existing [agents] table was modified"
  elif grep -q "WARNING" /tmp/smoke_install_out; then
    fail "config.toml has-agents-case: warned about a value that is already >= 4"
  else
    pass "config.toml has-agents-case: untouched, no needless warning"
  fi
else
  fail "config.toml has-agents-case: install failed"
fi

echo "=== 7/12: config.toml -- [agents] value too low (specific warning) ==="
CFG="$SCRATCH/cfg-lowagents/config.toml"
mkdir -p "$(dirname "$CFG")"
printf '[agents]\nmax_concurrent_threads_per_session = 2\n' > "$CFG"
BEFORE_HASH="$(sha256sum "$CFG" | cut -d' ' -f1)"
PROJ="$SCRATCH/cfg-lowagents-proj"
if ORCH_CODEX_CONFIG_PATH_OVERRIDE="$CFG" run_install codex "$PROJ"; then
  AFTER_HASH="$(sha256sum "$CFG" | cut -d' ' -f1)"
  if [ "$BEFORE_HASH" != "$AFTER_HASH" ]; then
    fail "config.toml low-agents-case: the file was modified"
  elif grep -q "max_concurrent_threads_per_session = 2, below the 8" /tmp/smoke_install_out; then
    pass "config.toml low-agents-case: warned with the actual value"
  else
    fail "config.toml low-agents-case: no specific warning: $(cat /tmp/smoke_install_out)"
  fi
else
  fail "config.toml low-agents-case: install failed"
fi

echo "=== 8/12: test writes enabled -- validator gains Edit/Write ==="
PROJ="$SCRATCH/testwrites-on"
if run_install claude "$PROJ" ORCH_ALLOW_TEST_WRITES=y; then
  pass "test-writes-on: install.sh exited 0"
  check_no_tokens "$PROJ/.claude" "test-writes-on"
  # verify-install.py ties the validator's Edit/Write allowlist to
  # validator.allowTestWrites, so this covers the "with" case too.
  check_verify "$PROJ/.claude" "test-writes-on"
  if grep -q '"allowTestWrites": true' "$PROJ/.claude/orchestration.json"; then
    pass "test-writes-on: orchestration.json records allowTestWrites=true"
  else
    fail "test-writes-on: orchestration.json still has allowTestWrites=false"
  fi
else
  fail "test-writes-on: install.sh failed: $(cat /tmp/smoke_install_out)"
fi

# A global install lands in ~/.claude, which on a real machine also holds
# session transcripts, credentials and plugin trees. The verifier must read
# only this bundle's files -- every other case installs project-scoped, which
# is exactly why an earlier whole-root scan went unnoticed.
echo "=== 9/12: global scope -- verifier must not read the rest of HOME ==="
FAKEHOME="$SCRATCH/fakehome"
DECOY="sk-decoy-DEADBEEF0123456789"
if env ORCH_NONINTERACTIVE=1 ORCH_PLATFORM=claude ORCH_SCOPE=global \
     HOME="$FAKEHOME" bash "$INSTALL" >/tmp/smoke_install_out 2>&1; then
  pass "global: install.sh exited 0"
  # Seeded INSIDE the install root, because that is where the real ones are:
  # ~/.claude/projects/*.jsonl and ~/.claude/.credentials.json. Seeding them
  # beside it would leave this case passing against the whole-root walk it
  # exists to catch.
  mkdir -p "$FAKEHOME/.claude/projects/junk"
  printf '{"apiKey": "%s"}\n' "$DECOY" > "$FAKEHOME/.claude/.credentials.json"
  i=0
  while [ $i -lt 300 ]; do
    printf 'token = "%s"\nfiller %d\n' "$DECOY" "$i" \
      > "$FAKEHOME/.claude/projects/junk/f$i.txt"
    i=$((i + 1))
  done
  start=$SECONDS
  verify_out="$("$PY" "$REPO_ROOT/templates/orchestrator-spec/verify-install.py" \
                  "$FAKEHOME/.claude" 2>&1)"
  verify_rc=$?
  elapsed=$((SECONDS - start))
  if [ $verify_rc -eq 0 ]; then
    pass "global: verify-install.py clean"
  else
    fail "global: verify-install.py: $verify_out"
  fi
  if printf '%s' "$verify_out" | grep -qF "$DECOY"; then
    fail "global: verifier echoed a credential value"
  else
    pass "global: verifier never echoed a credential value"
  fi
  if printf '%s' "$verify_out" | grep -qE 'credentials\.json|projects/junk'; then
    fail "global: verifier read files outside the bundle"
  else
    pass "global: verifier stayed inside the bundle's files"
  fi
  if [ "$elapsed" -le 15 ]; then
    pass "global: verify finished in ${elapsed}s"
  else
    fail "global: verify took ${elapsed}s -- it is walking the whole home dir"
  fi
else
  fail "global: install.sh failed: $(cat /tmp/smoke_install_out)"
fi

echo "=== 10/12: uninstall -- bundle gone, user's own files kept ==="
PROJ="$SCRATCH/uninstall"
if ORCH_CODEX_CONFIG_PATH_OVERRIDE="$PROJ/.codex/config.toml" run_install both "$PROJ"; then
  # Decoys: the failure this case exists for is an uninstall that takes the
  # user's own agents and skills with it.
  echo "mine" > "$PROJ/.claude/agents/my-own-agent.md"
  mkdir -p "$PROJ/.claude/skills/my-skill"
  echo "x" > "$PROJ/.claude/skills/my-skill/SKILL.md"
  if env ORCH_NONINTERACTIVE=1 ORCH_PLATFORM=both ORCH_SCOPE=project \
       ORCH_PROJECT_DIR="$PROJ" ORCH_UNINSTALL_CONFIRM=y \
       bash "$INSTALL" --uninstall > /tmp/smoke_uninstall_out 2>&1; then
    if [ -e "$PROJ/.claude/agents/task-orchestrator.md" ] ||
       [ -d "$PROJ/.claude/orchestrator-spec" ] ||
       [ -e "$PROJ/.claude/orchestration.json" ] ||
       [ -d "$PROJ/.claude/skills/orchestrate" ] ||
       [ -d "$PROJ/.codex/agents" ]; then
      fail "uninstall: bundle files survived"
    elif [ ! -f "$PROJ/.claude/agents/my-own-agent.md" ] ||
         [ ! -f "$PROJ/.claude/skills/my-skill/SKILL.md" ]; then
      fail "uninstall: removed files this bundle did not install"
    else
      pass "uninstall: bundle removed, user's own agents and skills kept"
    fi
  else
    fail "uninstall: --uninstall failed: $(cat /tmp/smoke_uninstall_out)"
  fi
else
  fail "uninstall: setup install failed: $(cat /tmp/smoke_install_out)"
fi

echo "=== 11/12: config UI -- fanned-out writes keep the install verifiable ==="
PROJ="$SCRATCH/config-ui"
if ORCH_CODEX_CONFIG_PATH_OVERRIDE="$PROJ/.codex/config.toml" run_install both "$PROJ"; then
  if "$PY" "$REPO_ROOT/tests/config-ui-test.py" \
       "$PROJ/.claude" "$PROJ/.codex" > /tmp/smoke_ui_out 2>&1; then
    pass "config UI: every setting reached all the files that must agree"
  else
    fail "config UI: $(grep '^FAIL' /tmp/smoke_ui_out | head -3)"
  fi
else
  fail "config UI: setup install failed: $(cat /tmp/smoke_install_out)"
fi

echo "=== 12/12: bootstrap.sh -- install without cloning ==="
PROJ="$SCRATCH/bootstrap"
mkdir -p "$PROJ"
# The bundle as it is right now, not as it was committed: a working-tree
# tarball is what the remote archive will be after the next push.
TARBALL="$SCRATCH/bundle.tar.gz"
if tar -czf "$TARBALL" -C "$(dirname "$REPO_ROOT")"      --exclude=.git --exclude=.smoke-test "$(basename "$REPO_ROOT")" 2>/dev/null; then
  # Own TMPDIR, so "did the bootstrap clean up after itself" is answerable.
  BOOT_TMP="$SCRATCH/boot-tmp"
  mkdir -p "$BOOT_TMP"
  if env ORCH_ARCHIVE_URL="$TARBALL" TMPDIR="$BOOT_TMP" ORCH_NONINTERACTIVE=1        ORCH_PLATFORM=claude ORCH_SCOPE=project ORCH_PROJECT_DIR="$PROJ"        ORCH_OVERWRITE=y bash "$REPO_ROOT/bootstrap.sh"        >/tmp/smoke_bootstrap_out 2>&1; then
    pass "bootstrap: bootstrap.sh exited 0"
    if [ -f "$PROJ/.claude/agents/task-orchestrator.md" ]; then
      pass "bootstrap: installed from the archive, no clone"
    else
      fail "bootstrap: nothing installed: $(tail -3 /tmp/smoke_bootstrap_out)"
    fi
    check_verify "$PROJ/.claude" "bootstrap"
    if [ -z "$(ls -A "$BOOT_TMP" 2>/dev/null)" ]; then
      pass "bootstrap: temp directory removed"
    else
      fail "bootstrap: left $(ls -A "$BOOT_TMP" | head -1) behind in TMPDIR"
    fi
  else
    fail "bootstrap: bootstrap.sh failed: $(tail -3 /tmp/smoke_bootstrap_out)"
  fi
else
  fail "bootstrap: could not build the test tarball"
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
