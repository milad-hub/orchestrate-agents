#!/usr/bin/env bash
# Installer for the orchestrate-agents bundle (manager/researcher/worker/
# validator/judge multi-agent system) -- Claude Code and/or Codex CLI.
#
# Usage: ./install.sh
#
# Non-interactive testing (never used for a real install -- for smoke tests
# only): set ORCH_NONINTERACTIVE=1 and optionally override any of:
#   ORCH_PLATFORM=claude|codex|both      (default claude)
#   ORCH_SCOPE=global|project
#   ORCH_PROJECT_DIR=<path>              (required if ORCH_SCOPE=project)
#   ORCH_OVERWRITE=y|n
#   ORCH_CODEX_CONFIG_PATH_OVERRIDE=<path>  (test-only; overrides
#                                             ~/.codex/config.toml target)
#
# Permission defaults. Both ship OFF and are NOT asked interactively --
# widening them is a deliberate decision, not a question to answer while
# skimming an installer. Honoured in interactive installs too:
#   ORCH_ALLOW_TEST_WRITES=y|n           (default n)
#   ORCH_ALLOW_BUILD_SERVE=y|n           (default n)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES="$REPO_ROOT/templates"

# ---- prompting helpers -----------------------------------------------

prompt() {
  # $1 = env var name to check in non-interactive mode
  # $2 = prompt text
  # $3 = default value
  local var="$1" text="$2" default="$3" reply
  if [ "${ORCH_NONINTERACTIVE:-0}" = "1" ]; then
    reply="${!var:-$default}"
  else
    read -r -p "$text [$default]: " reply || true
    reply="${reply:-$default}"
  fi
  printf '%s' "$reply"
}

# Arrow-key single-select menu. $1=prompt text, $2=default index, rest=options.
# Prints the chosen index on stdout; draws the menu on stderr.
# Redraws rewind a fixed number of rows, so a line that wraps would desync the
# cursor and leave a trail of half-drawn menus. Clip instead.
term_cols() {
  local cols
  cols="$(tput cols 2>/dev/null || echo 80)"
  case "$cols" in ''|*[!0-9]*) cols=80 ;; esac
  if [ "$cols" -lt 20 ]; then cols=20; fi
  printf '%d' "$((cols - 1))"
}

clip() {
  local text="$1" width="$2"
  printf '%s' "${text:0:width}"
}

radio_select() {
  local prompt_text="$1" cursor="$2"; shift 2
  local -a opts=("$@")
  local n=${#opts[@]} cols
  cols="$(term_cols)"
  local old_stty first=1
  old_stty="$(stty -g 2>/dev/null || true)"
  stty -icanon -echo min 1 time 0 2>/dev/null || true
  trap 'stty "$old_stty" 2>/dev/null; exit 130' INT TERM
  while :; do
    if [ "$first" -eq 1 ]; then first=0; else printf '\033[%dA' "$((n + 2))" >&2; fi
    printf '%s\n' "$(clip "$prompt_text" "$cols")" >&2
    local i=0
    for opt in "${opts[@]}"; do
      if [ "$i" -eq "$cursor" ]; then
        printf '%s\n' "$(clip "  > (x) $opt                    " "$cols")" >&2
      else
        printf '%s\n' "$(clip "    ( ) $opt                    " "$cols")" >&2
      fi
      i=$((i + 1))
    done
    printf '\n' >&2
    local key rest
    IFS= read -rsn1 key || true
    if [ "$key" = "$(printf '\033')" ]; then
      IFS= read -rsn2 -t 1 rest || true
      key="$key$rest"
    fi
    case "$key" in
      "$(printf '\033[A')") cursor=$(( (cursor - 1 + n) % n )) ;;
      "$(printf '\033[B')") cursor=$(( (cursor + 1) % n )) ;;
      ""|"$(printf '\n')"|"$(printf '\r')") break ;;
    esac
  done
  trap - INT TERM
  if [ -n "$old_stty" ]; then stty "$old_stty" 2>/dev/null || true; fi
  printf '%d' "$cursor"
}

# Arrow-key multi-select checkbox menu. $1=prompt text, $2=space-separated
# 0/1 defaults, rest=options. Prints space-separated 0/1 result on stdout.
checkbox_select() {
  local prompt_text="$1" defaults_str="$2"; shift 2
  local -a opts=("$@")
  local n=${#opts[@]} cols
  cols="$(term_cols)"
  local -a checked
  read -r -a checked <<< "$defaults_str"
  local cursor=0 old_stty first=1
  old_stty="$(stty -g 2>/dev/null || true)"
  stty -icanon -echo min 1 time 0 2>/dev/null || true
  trap 'stty "$old_stty" 2>/dev/null; exit 130' INT TERM
  while :; do
    if [ "$first" -eq 1 ]; then first=0; else printf '\033[%dA' "$((n + 2))" >&2; fi
    printf '%s\n' "$(clip "$prompt_text" "$cols")" >&2
    local i=0
    for opt in "${opts[@]}"; do
      local mark=" "
      if [ "${checked[$i]}" = "1" ]; then mark="x"; fi
      local pointer=" "
      if [ "$i" -eq "$cursor" ]; then pointer=">"; fi
      printf '%s\n' "$(clip "  $pointer [$mark] $opt                    " "$cols")" >&2
      i=$((i + 1))
    done
    printf '\n' >&2
    local key rest
    IFS= read -rsn1 key || true
    if [ "$key" = "$(printf '\033')" ]; then
      IFS= read -rsn2 -t 1 rest || true
      key="$key$rest"
    fi
    case "$key" in
      "$(printf '\033[A')") cursor=$(( (cursor - 1 + n) % n )) ;;
      "$(printf '\033[B')") cursor=$(( (cursor + 1) % n )) ;;
      " ") if [ "${checked[$cursor]}" = "1" ]; then checked[$cursor]=0; else checked[$cursor]=1; fi ;;
      ""|"$(printf '\n')"|"$(printf '\r')") break ;;
    esac
  done
  trap - INT TERM
  if [ -n "$old_stty" ]; then stty "$old_stty" 2>/dev/null || true; fi
  printf '%s' "${checked[*]}"
}

# Env-var only: for settings that are never asked interactively.
env_bool() {
  local var="$1" default="$2" reply
  reply="${!var:-$default}"
  case "$reply" in
    y|Y|yes|Yes|true|True) printf 'true' ;;
    *) printf 'false' ;;
  esac
}

prompt_bool() {
  local var="$1" text="$2" default="$3"
  if [ "${ORCH_NONINTERACTIVE:-0}" = "1" ]; then
    env_bool "$var" "$default"
    return
  fi
  local default_idx=1
  case "$default" in y|Y|yes|Yes|true|True) default_idx=0 ;; esac
  local idx
  idx="$(radio_select "$text (Up/Down move, Enter confirm):" "$default_idx" "Yes" "No")"
  if [ "$idx" = "0" ]; then printf 'true'; else printf 'false'; fi
}

# ---- 1. platform choice -------------------------------------------------

if [ "${ORCH_NONINTERACTIVE:-0}" = "1" ]; then
  platform_ans="${ORCH_PLATFORM:-claude}"
else
  result="$(checkbox_select "Install for: (Up/Down move, Space toggle, Enter confirm)" "1 0" "Claude Code" "Codex CLI")"
  read -r sel_claude_n sel_codex_n <<< "$result"
  sel_claude=false
  sel_codex=false
  if [ "$sel_claude_n" = "1" ]; then sel_claude=true; fi
  if [ "$sel_codex_n" = "1" ]; then sel_codex=true; fi
  if ! $sel_claude && ! $sel_codex; then sel_claude=true; fi
  if $sel_claude && $sel_codex; then
    platform_ans="both"
  elif $sel_codex; then
    platform_ans="codex"
  else
    platform_ans="claude"
  fi
fi
case "$platform_ans" in
  claude|codex|both) : ;;
  *) echo "Error: unrecognized platform '$platform_ans' (expected claude, codex, or both)." >&2; exit 1 ;;
esac
WANT_CLAUDE=false
WANT_CODEX=false
if [ "$platform_ans" = "claude" ] || [ "$platform_ans" = "both" ]; then WANT_CLAUDE=true; fi
if [ "$platform_ans" = "codex" ] || [ "$platform_ans" = "both" ]; then WANT_CODEX=true; fi
echo "Platform(s): $platform_ans"

# ---- 2. scope ----------------------------------------------------------

if [ "${ORCH_NONINTERACTIVE:-0}" = "1" ]; then
  scope_ans="${ORCH_SCOPE:-global}"
else
  global_dirs=""
  if $WANT_CLAUDE; then global_dirs="~/.claude"; fi
  if $WANT_CODEX; then
    if [ -n "$global_dirs" ]; then global_dirs="$global_dirs, ~/.codex"; else global_dirs="~/.codex"; fi
  fi
  project_dirs=""
  if $WANT_CLAUDE; then project_dirs=".claude/"; fi
  if $WANT_CODEX; then
    if [ -n "$project_dirs" ]; then project_dirs="$project_dirs, .codex/"; else project_dirs=".codex/"; fi
  fi
  scope_idx="$(radio_select "Install scope (Up/Down move, Enter confirm):" 0 "Install globally ($global_dirs)" "Install into a project ($project_dirs)")"
  if [ "$scope_idx" = "1" ]; then scope_ans="project"; else scope_ans="global"; fi
fi

if [ "$scope_ans" = "project" ]; then
  if [ "${ORCH_NONINTERACTIVE:-0}" = "1" ]; then
    project_dir="${ORCH_PROJECT_DIR:?ORCH_PROJECT_DIR is required when ORCH_SCOPE=project}"
  else
    read -r -p "Project directory path: " project_dir
  fi
  project_dir="${project_dir/#\~/$HOME}"
  [ -d "$project_dir" ] || { echo "Error: '$project_dir' is not a directory." >&2; exit 1; }
  project_dir="$(cd "$project_dir" && pwd)"
  TARGET_CLAUDE_DIR="$project_dir/.claude"
  TARGET_CODEX_DIR="$project_dir/.codex"
else
  TARGET_CLAUDE_DIR="$HOME/.claude"
  TARGET_CODEX_DIR="$HOME/.codex"
fi

if $WANT_CLAUDE; then echo "Claude Code target: $TARGET_CLAUDE_DIR"; fi
if $WANT_CODEX; then echo "Codex CLI target: $TARGET_CODEX_DIR"; fi

# ---- 3. overwrite check -------------------------------------------------

existing=""
if $WANT_CLAUDE && [ -f "$TARGET_CLAUDE_DIR/agents/task-orchestrator.md" ]; then existing="$existing $TARGET_CLAUDE_DIR"; fi
if $WANT_CODEX && [ -f "$TARGET_CODEX_DIR/agents/task-orchestrator.md" ]; then existing="$existing $TARGET_CODEX_DIR"; fi
if [ -n "$existing" ]; then
  if [ "${ORCH_NONINTERACTIVE:-0}" != "1" ]; then
    echo "Existing orchestration install found at:$existing"
  fi
  overwrite="$(prompt_bool ORCH_OVERWRITE "Overwrite it" n)"
  if [ "$overwrite" != "true" ]; then
    echo "Aborted -- nothing was changed."
    exit 0
  fi
fi

# ---- 4. workflow toggles -------------------------------------------------

# Not asked. Both default OFF -- the safe setting -- and stay a permission
# decision the user makes deliberately. /orchestrate-sync flips them (and
# the validator's tool allowlist with them) on request.
ALLOW_TEST_WRITES="$(env_bool ORCH_ALLOW_TEST_WRITES n)"
ALLOW_BUILD_SERVE="$(env_bool ORCH_ALLOW_BUILD_SERVE n)"

# The validator only gets Edit/Write in its Claude tools allowlist when test
# writes are on -- with the default off the harness keeps it read-only, so the
# rule doesn't depend on the prompt being obeyed.
if [ "$ALLOW_TEST_WRITES" = "true" ]; then
  VALIDATOR_WRITE_TOOLS=", Edit, Write"
else
  VALIDATOR_WRITE_TOOLS=""
fi

# ---- 5. misc tokens ------------------------------------------------------

INSTALL_DATE="$(date +%Y-%m-%d)"
CLAUDE_VERSION="unknown -- run /orchestrate-sync"
CODEX_VERSION="unknown -- run /orchestrate-sync"
if $WANT_CLAUDE && command -v claude >/dev/null 2>&1; then
  v="$(claude --version 2>/dev/null | head -n1 || true)"
  if [ -n "$v" ]; then CLAUDE_VERSION="$v"; fi
fi
if $WANT_CODEX && command -v codex >/dev/null 2>&1; then
  v="$(codex --version 2>/dev/null | head -n1 || true)"
  if [ -n "$v" ]; then CODEX_VERSION="$v"; fi
fi

# ---- substitution --------------------------------------------------------

esc() { printf '%s' "$1" | sed -e 's/[&#\]/\\&/g'; }

# agent_home_dir_current is set right before each orchestrator-spec copy
# pass below (it resolves to whichever platform's target dir that pass is
# writing into); CLAUDE_DIR/CODEX_DIR tokens are fixed for the whole run.
agent_home_dir_current=""

# The sed program is identical for every file in a platform pass, so build
# it once (into the SED_OPTS array) instead of re-running ~12 esc subshells
# and re-assembling the args per file -- a big win on Windows where each
# subshell/process spawn is costly and copy_tree touches ~58 files.
SED_OPTS=()
build_sed_opts() {
  SED_OPTS=(
    -e "s#{{AGENT_HOME_DIR}}#$(esc "$agent_home_dir_current")#g"
    -e "s#{{CLAUDE_DIR}}#$(esc "$TARGET_CLAUDE_DIR")#g"
    -e "s#{{CODEX_DIR}}#$(esc "$TARGET_CODEX_DIR")#g"
    -e "s/{{ALLOW_WORKER_TEST_WRITES}}/${ALLOW_TEST_WRITES}/g"
    -e "s/{{ALLOW_VALIDATOR_TEST_WRITES}}/${ALLOW_TEST_WRITES}/g"
    -e "s/{{ALLOW_TEST_FILE_CREATION}}/${ALLOW_TEST_WRITES}/g"
    -e "s/{{ALLOW_BUILD_COMMANDS}}/${ALLOW_BUILD_SERVE}/g"
    -e "s/{{ALLOW_SERVE_COMMANDS}}/${ALLOW_BUILD_SERVE}/g"
    -e "s/{{ALLOW_VALIDATOR_BUILD_COMMANDS}}/${ALLOW_BUILD_SERVE}/g"
    -e "s/{{ALLOW_VALIDATOR_SERVE_COMMANDS}}/${ALLOW_BUILD_SERVE}/g"
    -e "s#{{VALIDATOR_WRITE_TOOLS}}#${VALIDATOR_WRITE_TOOLS}#g"
    -e "s/{{INSTALL_DATE}}/${INSTALL_DATE}/g"
    -e "s#{{CLAUDE_VERSION}}#$(esc "$CLAUDE_VERSION")#g"
    -e "s#{{CODEX_VERSION}}#$(esc "$CODEX_VERSION")#g"
  )
}

substitute() {
  sed "${SED_OPTS[@]}" "$1" > "$2"
}

copy_tree() {
  local src_root="$1" dst_root="$2" f rel dst
  find "$src_root" -type f | while IFS= read -r f; do
    rel="${f#"$src_root"/}"
    dst="$dst_root/$rel"
    mkdir -p "$(dirname "$dst")"
    substitute "$f" "$dst"
  done
}

# ---- 6. config.toml [agents] merge (Codex only, always global) --------

# Must be >= workflow.maximumParallelWorkers in orchestration.template.json.
REQUIRED_THREADS=4

# The value of max_concurrent_threads_per_session inside the [agents] table,
# or empty if the table has no such key. Scoped to that table so an identically
# named key under another section cannot be mistaken for it.
codex_thread_limit() {
  awk '/^[[:space:]]*\[agents\][[:space:]]*$/ {inside = 1; next}
       /^[[:space:]]*\[/ {inside = 0}
       inside' "$1" \
    | sed -n 's/^[[:space:]]*max_concurrent_threads_per_session[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' \
    | head -n 1
}

merge_codex_config() {
  local codex_config="${ORCH_CODEX_CONFIG_PATH_OVERRIDE:-$HOME/.codex/config.toml}"
  local limit
  if [ ! -f "$codex_config" ]; then
    mkdir -p "$(dirname "$codex_config")"
    printf '[agents]\nmax_concurrent_threads_per_session = %s\n' "$REQUIRED_THREADS" > "$codex_config"
    echo "Created $codex_config with a default [agents] table."
  elif grep -q '^[[:space:]]*\[agents\][[:space:]]*$' "$codex_config"; then
    # Never modified -- an existing [agents] table is the user's. But there is
    # no reason to make them go read a number the installer can read.
    limit="$(codex_thread_limit "$codex_config")"
    if [ -z "$limit" ]; then
      echo "WARNING: $codex_config has an [agents] table with no"
      echo "max_concurrent_threads_per_session. Add"
      echo "'max_concurrent_threads_per_session = $REQUIRED_THREADS' to it, or the"
      echo "manager may not get the $REQUIRED_THREADS parallel delegates it plans for."
    elif [ "$limit" -lt "$REQUIRED_THREADS" ]; then
      echo "WARNING: $codex_config sets"
      echo "max_concurrent_threads_per_session = $limit, below the $REQUIRED_THREADS parallel"
      echo "delegates the manager plans for. Raise it to $REQUIRED_THREADS or delegates will"
      echo "queue. Your config was not modified."
    fi
  else
    printf '\n[agents]\nmax_concurrent_threads_per_session = %s\n' "$REQUIRED_THREADS" >> "$codex_config"
    echo "Appended [agents] table to $codex_config."
  fi
}

# ---- 7. generate ----------------------------------------------------------

BUNDLE_VERSION=7
KEPT_CONFIG=""

# Skill directories this bundle shipped under a previous name. copy_tree only
# writes files, so without this a rename leaves the old skill installed
# alongside the new one -- both register, and the stale copy describes a
# procedure that no longer matches the verifier it calls.
RETIRED_SKILLS="orchestrate-update"

remove_retired_skills() {
  local dir="$1" name
  for name in $RETIRED_SKILLS; do
    if [ -d "$dir/skills/$name" ]; then
      rm -rf "$dir/skills/$name"
      REMOVED_SKILLS="$REMOVED_SKILLS $dir/skills/$name"
    fi
  done
}
REMOVED_SKILLS=""

# Reinstalling replaces the generated tree -- that is what upgrading means --
# but orchestration.json is not generated content. It carries the models,
# effort, permission flags and reconciled deny list that /orchestrate-sync
# wrote for THIS machine, so keep it and let the user reconcile.
# A stale prompt-hashes.json would mismatch the new prompts on every upgrade,
# so drop it; the next /orchestrate-sync re-blesses.
install_config() {
  local dir="$1"
  rm -f "$dir/orchestrator-spec/prompt-hashes.json"
  if [ -f "$dir/orchestration.json" ]; then
    KEPT_CONFIG="$KEPT_CONFIG $dir"
  else
    cp "$dir/orchestrator-spec/orchestration.template.json" "$dir/orchestration.json"
  fi
}

# Machine-readable install facts. /orchestrate-sync's fast path compares
# cliVersion against `claude --version` / `codex --version` and writes back
# what it saw -- parsing prose out of a README was the previous design and it
# referred to a line that did not exist.
write_install_state() {
  printf '{\n  "platform": "%s",\n  "bundleVersion": %s,\n  "installedAt": "%s",\n  "cliVersion": null,\n  "lastCheckedAt": null\n}\n' \
    "$2" "$BUNDLE_VERSION" "$(date +%Y-%m-%d)" \
    > "$1/orchestrator-spec/install-state.json"
}

if $WANT_CLAUDE; then
  mkdir -p "$TARGET_CLAUDE_DIR"
  agent_home_dir_current="$TARGET_CLAUDE_DIR"
  build_sed_opts
  copy_tree "$TEMPLATES/orchestrator-spec" "$TARGET_CLAUDE_DIR/orchestrator-spec"
  copy_tree "$TEMPLATES/agents" "$TARGET_CLAUDE_DIR/agents"
  copy_tree "$TEMPLATES/skills" "$TARGET_CLAUDE_DIR/skills"
  substitute "$TEMPLATES/README-orchestration.template.md" "$TARGET_CLAUDE_DIR/README-orchestration.md"
  remove_retired_skills "$TARGET_CLAUDE_DIR"
  install_config "$TARGET_CLAUDE_DIR"
  write_install_state "$TARGET_CLAUDE_DIR" claude
fi

if $WANT_CODEX; then
  mkdir -p "$TARGET_CODEX_DIR"
  agent_home_dir_current="$TARGET_CODEX_DIR"
  build_sed_opts
  copy_tree "$TEMPLATES/orchestrator-spec" "$TARGET_CODEX_DIR/orchestrator-spec"
  copy_tree "$TEMPLATES/codex/agents" "$TARGET_CODEX_DIR/agents"
  copy_tree "$TEMPLATES/codex/skills" "$TARGET_CODEX_DIR/skills"
  substitute "$TEMPLATES/codex/README-orchestration.template.md" "$TARGET_CODEX_DIR/README-orchestration.md"
  remove_retired_skills "$TARGET_CODEX_DIR"
  install_config "$TARGET_CODEX_DIR"
  write_install_state "$TARGET_CODEX_DIR" codex
  merge_codex_config
fi

# One closing message. The next step is identical on both platforms, so
# saying it twice in different words only makes it easier to skip.
TARGETS=""
if $WANT_CLAUDE; then TARGETS="$TARGET_CLAUDE_DIR"; fi
if $WANT_CODEX; then
  if [ -n "$TARGETS" ]; then TARGETS="$TARGETS, $TARGET_CODEX_DIR"
  else TARGETS="$TARGET_CODEX_DIR"; fi
fi

echo ""
echo "Installed to $TARGETS."
if [ -n "$REMOVED_SKILLS" ]; then
  echo "Removed skills renamed in this bundle:$REMOVED_SKILLS"
fi
if [ -n "$KEPT_CONFIG" ]; then
  echo "Kept your existing orchestration.json (models, effort, permission"
  echo "flags, capability deny list). Tool allowlists and MCP routing were"
  echo "reset to the bundle defaults."
fi
echo ""
echo "Next: open a session and run /orchestrate-sync -- once per platform you"
echo "installed. It reconciles tool allowlists, MCP routing and the capability"
echo "deny list against THIS machine, and records the prompt hashes it checks"
echo "against later. Recommended before your first real /orchestrate run; the"
echo "bundle works without it, just conservatively."
