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
#   ORCH_ROLE_ORCHESTRATOR=model/effort  (default opus/high)
#   ORCH_ROLE_RESEARCHER=model/effort    (default haiku/medium)
#   ORCH_ROLE_WORKER=model/effort        (default haiku/medium)
#   ORCH_ROLE_VALIDATOR=model/effort     (default haiku/medium)
#   ORCH_ROLE_JUDGE=model/effort         (default sonnet/high)
#   ORCH_ALLOW_TEST_WRITES=y|n           (default n)
#   ORCH_ALLOW_BUILD_SERVE=y|n           (default n)
#   ORCH_CODEX_MODEL_RESEARCHER=<id>     (default blank = inherit session model)
#   ORCH_CODEX_MODEL_WORKER=<id>
#   ORCH_CODEX_MODEL_VALIDATOR=<id>
#   ORCH_CODEX_MODEL_JUDGE=<id>
#   ORCH_CODEX_CONFIG_PATH_OVERRIDE=<path>  (test-only; overrides
#                                             ~/.codex/config.toml target)

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
radio_select() {
  local prompt_text="$1" cursor="$2"; shift 2
  local -a opts=("$@")
  local n=${#opts[@]}
  local old_stty first=1
  old_stty="$(stty -g 2>/dev/null || true)"
  stty -icanon -echo min 1 time 0 2>/dev/null || true
  trap 'stty "$old_stty" 2>/dev/null; exit 130' INT TERM
  while :; do
    if [ "$first" -eq 1 ]; then first=0; else printf '\033[%dA' "$((n + 2))" >&2; fi
    printf '%s\n' "$prompt_text" >&2
    local i=0
    for opt in "${opts[@]}"; do
      if [ "$i" -eq "$cursor" ]; then
        printf '  > (x) %s                    \n' "$opt" >&2
      else
        printf '    ( ) %s                    \n' "$opt" >&2
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
  local n=${#opts[@]}
  local -a checked
  read -r -a checked <<< "$defaults_str"
  local cursor=0 old_stty first=1
  old_stty="$(stty -g 2>/dev/null || true)"
  stty -icanon -echo min 1 time 0 2>/dev/null || true
  trap 'stty "$old_stty" 2>/dev/null; exit 130' INT TERM
  while :; do
    if [ "$first" -eq 1 ]; then first=0; else printf '\033[%dA' "$((n + 2))" >&2; fi
    printf '%s\n' "$prompt_text" >&2
    local i=0
    for opt in "${opts[@]}"; do
      local mark=" "
      if [ "${checked[$i]}" = "1" ]; then mark="x"; fi
      local pointer=" "
      if [ "$i" -eq "$cursor" ]; then pointer=">"; fi
      printf '  %s [%s] %s                    \n' "$pointer" "$mark" "$opt" >&2
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

prompt_bool() {
  local var="$1" text="$2" default="$3" reply
  if [ "${ORCH_NONINTERACTIVE:-0}" = "1" ]; then
    reply="${!var:-$default}"
    case "$reply" in
      y|Y|yes|Yes|true|True) printf 'true' ;;
      *) printf 'false' ;;
    esac
    return
  fi
  local default_idx=1
  case "$default" in y|Y|yes|Yes|true|True) default_idx=0 ;; esac
  local idx
  idx="$(radio_select "$text (Up/Down move, Enter confirm):" "$default_idx" "Yes" "No")"
  if [ "$idx" = "0" ]; then printf 'true'; else printf 'false'; fi
}

role_prompt() {
  local var="$1" label="$2" default_model="$3" default_effort="$4" show_model="$5"
  if [ "${ORCH_NONINTERACTIVE:-0}" = "1" ]; then
    printf '%s' "${!var:-${default_model}/${default_effort}}"
    return
  fi
  local model="$default_model"
  if [ "$show_model" = "1" ]; then
    local -a models=(opus sonnet haiku)
    local model_idx=0 i=0
    for m in "${models[@]}"; do
      if [ "$m" = "$default_model" ]; then model_idx=$i; fi
      i=$((i + 1))
    done
    local mi
    mi="$(radio_select "$label -- model (Up/Down move, Enter confirm):" "$model_idx" "${models[@]}")"
    model="${models[$mi]}"
  fi
  local -a efforts=(low medium high)
  local effort_idx=1 i=0
  for e in "${efforts[@]}"; do
    if [ "$e" = "$default_effort" ]; then effort_idx=$i; fi
    i=$((i + 1))
  done
  local ei
  ei="$(radio_select "$label -- effort (Up/Down move, Enter confirm):" "$effort_idx" "${efforts[@]}")"
  printf '%s/%s' "$model" "${efforts[$ei]}"
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
  overwrite="$(prompt_bool ORCH_OVERWRITE "Existing orchestration install found at:$existing. Overwrite" n)"
  if [ "$overwrite" != "true" ]; then
    echo "Aborted -- nothing was changed."
    exit 0
  fi
fi

# ---- 4. per-role model/effort (always asked; Codex reuses the effort) --

show_model=0
if $WANT_CLAUDE; then show_model=1; fi
role_orchestrator="$(role_prompt ORCH_ROLE_ORCHESTRATOR "Manager (task-orchestrator)" opus high "$show_model")"
role_researcher="$(role_prompt ORCH_ROLE_RESEARCHER "Researcher (codebase-researcher)" haiku medium "$show_model")"
role_worker="$(role_prompt ORCH_ROLE_WORKER "Worker (implementation-worker)" haiku medium "$show_model")"
role_validator="$(role_prompt ORCH_ROLE_VALIDATOR "Validator (test-validator)" haiku medium "$show_model")"
role_judge="$(role_prompt ORCH_ROLE_JUDGE "Judge (result-judge)" sonnet high "$show_model")"

MODEL_ORCHESTRATOR="${role_orchestrator%%/*}";  EFFORT_ORCHESTRATOR="${role_orchestrator##*/}"
MODEL_RESEARCHER="${role_researcher%%/*}";       EFFORT_RESEARCHER="${role_researcher##*/}"
MODEL_WORKER="${role_worker%%/*}";               EFFORT_WORKER="${role_worker##*/}"
MODEL_VALIDATOR="${role_validator%%/*}";         EFFORT_VALIDATOR="${role_validator##*/}"
MODEL_JUDGE="${role_judge%%/*}";                 EFFORT_JUDGE="${role_judge##*/}"

# ---- 5. Codex model overrides (only if Codex is a target) ---------------

REASONING_EFFORT_RESEARCHER="$EFFORT_RESEARCHER"
REASONING_EFFORT_WORKER="$EFFORT_WORKER"
REASONING_EFFORT_VALIDATOR="$EFFORT_VALIDATOR"
REASONING_EFFORT_JUDGE="$EFFORT_JUDGE"

MODEL_OVERRIDE_RESEARCHER=""; MODEL_COMMENT_RESEARCHER="# "
MODEL_OVERRIDE_WORKER="";     MODEL_COMMENT_WORKER="# "
MODEL_OVERRIDE_VALIDATOR="";  MODEL_COMMENT_VALIDATOR="# "
MODEL_OVERRIDE_JUDGE="";      MODEL_COMMENT_JUDGE="# "

if $WANT_CODEX; then
  MODEL_OVERRIDE_RESEARCHER="$(prompt ORCH_CODEX_MODEL_RESEARCHER "Codex model override for researcher (blank = inherit session default)" "")"
  MODEL_OVERRIDE_WORKER="$(prompt ORCH_CODEX_MODEL_WORKER "Codex model override for worker (blank = inherit session default)" "")"
  MODEL_OVERRIDE_VALIDATOR="$(prompt ORCH_CODEX_MODEL_VALIDATOR "Codex model override for validator (blank = inherit session default)" "")"
  MODEL_OVERRIDE_JUDGE="$(prompt ORCH_CODEX_MODEL_JUDGE "Codex model override for judge (blank = inherit session default)" "")"
  if [ -n "$MODEL_OVERRIDE_RESEARCHER" ]; then MODEL_COMMENT_RESEARCHER=""; else MODEL_OVERRIDE_RESEARCHER="not set -- inherits session default"; fi
  if [ -n "$MODEL_OVERRIDE_WORKER" ]; then MODEL_COMMENT_WORKER=""; else MODEL_OVERRIDE_WORKER="not set -- inherits session default"; fi
  if [ -n "$MODEL_OVERRIDE_VALIDATOR" ]; then MODEL_COMMENT_VALIDATOR=""; else MODEL_OVERRIDE_VALIDATOR="not set -- inherits session default"; fi
  if [ -n "$MODEL_OVERRIDE_JUDGE" ]; then MODEL_COMMENT_JUDGE=""; else MODEL_OVERRIDE_JUDGE="not set -- inherits session default"; fi
fi

# ---- 6. workflow toggles -------------------------------------------------

ALLOW_TEST_WRITES="$(prompt_bool ORCH_ALLOW_TEST_WRITES "Allow workers/validator to create or modify test files by default" n)"
ALLOW_BUILD_SERVE="$(prompt_bool ORCH_ALLOW_BUILD_SERVE "Allow build and serve/dev-server commands by default" n)"

# ---- 7. misc tokens ------------------------------------------------------

INSTALL_DATE="$(date +%Y-%m-%d)"
CLAUDE_VERSION="unknown -- run /orchestrate-update"
CODEX_VERSION="unknown -- run /orchestrate-update"
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
model_platform_current=""

# The sed program is identical for every file in a platform pass, so build
# it once (into the SED_OPTS array) instead of re-running ~12 esc subshells
# and re-assembling the args per file -- a big win on Windows where each
# subshell/process spawn is costly and copy_tree touches ~58 files.
SED_OPTS=()
build_sed_opts() {
  local mo mr mw mv mj
  if [ "$model_platform_current" = "codex" ]; then
    mo="inherits Codex session default"
    mr="$MODEL_OVERRIDE_RESEARCHER"
    mw="$MODEL_OVERRIDE_WORKER"
    mv="$MODEL_OVERRIDE_VALIDATOR"
    mj="$MODEL_OVERRIDE_JUDGE"
  else
    mo="$MODEL_ORCHESTRATOR"
    mr="$MODEL_RESEARCHER"
    mw="$MODEL_WORKER"
    mv="$MODEL_VALIDATOR"
    mj="$MODEL_JUDGE"
  fi
  SED_OPTS=(
    -e "s#{{AGENT_HOME_DIR}}#$(esc "$agent_home_dir_current")#g"
    -e "s#{{CLAUDE_DIR}}#$(esc "$TARGET_CLAUDE_DIR")#g"
    -e "s#{{CODEX_DIR}}#$(esc "$TARGET_CODEX_DIR")#g"
    -e "s#{{MODEL_ORCHESTRATOR}}#$(esc "$mo")#g"
    -e "s/{{EFFORT_ORCHESTRATOR}}/${EFFORT_ORCHESTRATOR}/g"
    -e "s#{{MODEL_RESEARCHER}}#$(esc "$mr")#g"
    -e "s/{{EFFORT_RESEARCHER}}/${EFFORT_RESEARCHER}/g"
    -e "s#{{MODEL_WORKER}}#$(esc "$mw")#g"
    -e "s/{{EFFORT_WORKER}}/${EFFORT_WORKER}/g"
    -e "s#{{MODEL_VALIDATOR}}#$(esc "$mv")#g"
    -e "s/{{EFFORT_VALIDATOR}}/${EFFORT_VALIDATOR}/g"
    -e "s#{{MODEL_JUDGE}}#$(esc "$mj")#g"
    -e "s/{{EFFORT_JUDGE}}/${EFFORT_JUDGE}/g"
    -e "s/{{REASONING_EFFORT_RESEARCHER}}/${REASONING_EFFORT_RESEARCHER}/g"
    -e "s/{{REASONING_EFFORT_WORKER}}/${REASONING_EFFORT_WORKER}/g"
    -e "s/{{REASONING_EFFORT_VALIDATOR}}/${REASONING_EFFORT_VALIDATOR}/g"
    -e "s/{{REASONING_EFFORT_JUDGE}}/${REASONING_EFFORT_JUDGE}/g"
    -e "s#{{MODEL_OVERRIDE_RESEARCHER}}#$(esc "$MODEL_OVERRIDE_RESEARCHER")#g"
    -e "s#{{MODEL_OVERRIDE_WORKER}}#$(esc "$MODEL_OVERRIDE_WORKER")#g"
    -e "s#{{MODEL_OVERRIDE_VALIDATOR}}#$(esc "$MODEL_OVERRIDE_VALIDATOR")#g"
    -e "s#{{MODEL_OVERRIDE_JUDGE}}#$(esc "$MODEL_OVERRIDE_JUDGE")#g"
    -e "s/{{MODEL_COMMENT_RESEARCHER}}/${MODEL_COMMENT_RESEARCHER}/g"
    -e "s/{{MODEL_COMMENT_WORKER}}/${MODEL_COMMENT_WORKER}/g"
    -e "s/{{MODEL_COMMENT_VALIDATOR}}/${MODEL_COMMENT_VALIDATOR}/g"
    -e "s/{{MODEL_COMMENT_JUDGE}}/${MODEL_COMMENT_JUDGE}/g"
    -e "s/{{ALLOW_WORKER_TEST_WRITES}}/${ALLOW_TEST_WRITES}/g"
    -e "s/{{ALLOW_VALIDATOR_TEST_WRITES}}/${ALLOW_TEST_WRITES}/g"
    -e "s/{{ALLOW_TEST_FILE_CREATION}}/${ALLOW_TEST_WRITES}/g"
    -e "s/{{ALLOW_BUILD_COMMANDS}}/${ALLOW_BUILD_SERVE}/g"
    -e "s/{{ALLOW_SERVE_COMMANDS}}/${ALLOW_BUILD_SERVE}/g"
    -e "s/{{ALLOW_VALIDATOR_BUILD_COMMANDS}}/${ALLOW_BUILD_SERVE}/g"
    -e "s/{{ALLOW_VALIDATOR_SERVE_COMMANDS}}/${ALLOW_BUILD_SERVE}/g"
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

# ---- 8. config.toml [agents] merge (Codex only, always global) --------

merge_codex_config() {
  local codex_config="${ORCH_CODEX_CONFIG_PATH_OVERRIDE:-$HOME/.codex/config.toml}"
  if [ ! -f "$codex_config" ]; then
    mkdir -p "$(dirname "$codex_config")"
    printf '[agents]\nmax_concurrent_threads_per_session = 4\n' > "$codex_config"
    echo "Created $codex_config with a default [agents] table."
  elif grep -q '^\[agents\]' "$codex_config"; then
    echo "WARNING: $codex_config already has an [agents] section -- not modified. Verify max_concurrent_threads_per_session yourself (should be >= workflow.maximumParallelWorkers in orchestration.json, default 4)."
  else
    printf '\n[agents]\nmax_concurrent_threads_per_session = 4\n' >> "$codex_config"
    echo "Appended [agents] table to $codex_config."
  fi
}

# ---- 9. generate ----------------------------------------------------------

if $WANT_CLAUDE; then
  mkdir -p "$TARGET_CLAUDE_DIR"
  agent_home_dir_current="$TARGET_CLAUDE_DIR"
  model_platform_current="claude"
  build_sed_opts
  copy_tree "$TEMPLATES/orchestrator-spec" "$TARGET_CLAUDE_DIR/orchestrator-spec"
  copy_tree "$TEMPLATES/agents" "$TARGET_CLAUDE_DIR/agents"
  copy_tree "$TEMPLATES/skills" "$TARGET_CLAUDE_DIR/skills"
  substitute "$TEMPLATES/README-orchestration.template.md" "$TARGET_CLAUDE_DIR/README-orchestration.md"
  cp "$TARGET_CLAUDE_DIR/orchestrator-spec/orchestration.template.json" "$TARGET_CLAUDE_DIR/orchestration.json"
fi

if $WANT_CODEX; then
  mkdir -p "$TARGET_CODEX_DIR"
  agent_home_dir_current="$TARGET_CODEX_DIR"
  model_platform_current="codex"
  build_sed_opts
  copy_tree "$TEMPLATES/orchestrator-spec" "$TARGET_CODEX_DIR/orchestrator-spec"
  copy_tree "$TEMPLATES/codex/agents" "$TARGET_CODEX_DIR/agents"
  copy_tree "$TEMPLATES/codex/skills" "$TARGET_CODEX_DIR/skills"
  substitute "$TEMPLATES/codex/README-orchestration.template.md" "$TARGET_CODEX_DIR/README-orchestration.md"
  cp "$TARGET_CODEX_DIR/orchestrator-spec/orchestration.template.json" "$TARGET_CODEX_DIR/orchestration.json"
  merge_codex_config
fi

echo ""
if $WANT_CLAUDE; then echo "Installed to $TARGET_CLAUDE_DIR."; fi
if $WANT_CODEX; then echo "Installed to $TARGET_CODEX_DIR."; fi
echo ""
if $WANT_CLAUDE; then
  echo "Next (Claude Code): open a session and run /orchestrate-update to"
  echo "reconcile MCP tool allowlists and the capability denylist against"
  echo "THIS machine's installed plugins/MCP servers."
fi
if $WANT_CODEX; then
  echo "Next (Codex CLI): open a session and run /orchestrate-update to"
  echo "reconcile MCP server routing and the capability denylist against"
  echo "THIS machine's installed MCP servers."
fi
echo "Required before your first real /orchestrate run for full capability"
echo "coverage -- the bundle works without it too, just conservatively."
