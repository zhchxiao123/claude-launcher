#!/usr/bin/env bash
set -uo pipefail

VERSION="1.0.0"
SCRIPT_NAME="$(basename "$0")"

# ── Color support ────────────────────────────────────────────
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]] && [[ -z "${CLAUDE_LAUNCHER_NO_COLOR:-}" ]]; then
  RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m'
  BLUE='\033[0;34m' BOLD='\033[1m' NC='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' BOLD='' NC=''
fi

die() { printf "${RED}Error:${NC} %s\n" "$1" >&2; exit 1; }
warn() { printf "${YELLOW}Warning:${NC} %s\n" "$1" >&2; }

# ── Help ─────────────────────────────────────────────────────
show_help() {
  cat <<'HELP'
Claude Launcher - Switch Claude Code model presets from a menu.

Usage:
  install.sh                     Install claude-launcher to ~/.config
  claude-launcher                Launch: select a preset, start Claude Code
  claude-launcher models         Manage presets (list, add, edit, remove)
  claude-launcher uninstall      Remove Claude Launcher entirely
  claude-launcher -h, --help     Show this help

Environment:
  CLAUDE_LAUNCHER_CONFIG        Path to a custom presets.json
  CLAUDE_LAUNCHER_NO_COLOR      Disable colored output
  NO_COLOR                      Disable colored output (standard)

Examples:
  claude-launcher
  claude-launcher models
  CLAUDE_LAUNCHER_CONFIG=./my.json claude-launcher
  NO_COLOR=1 claude-launcher
HELP
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  show_help; exit 0
fi

# ── Config path resolution ───────────────────────────────────
DEFAULT_CONFIG="$HOME/.config/claude-launcher/presets.json"

resolve_config() {
  if [[ -n "${CLAUDE_LAUNCHER_CONFIG:-}" ]]; then
    CONFIG_FILE="$CLAUDE_LAUNCHER_CONFIG"
    if [[ "$CONFIG_FILE" != /* ]]; then
      CONFIG_FILE="$(pwd)/$CONFIG_FILE"
    fi
  else
    CONFIG_FILE="$DEFAULT_CONFIG"
  fi
}

# ── JSON parser detection ────────────────────────────────────
detect_parser() {
  if command -v jq &>/dev/null; then
    JSON_PARSE_MODE="jq"
  elif command -v python3 &>/dev/null; then
    JSON_PARSE_MODE="python"
    PYTHON_BIN="python3"
  elif command -v python &>/dev/null; then
    JSON_PARSE_MODE="python"
    PYTHON_BIN="python"
  else
    die "Neither jq nor python3 found. Install jq: brew install jq / apt install jq"
  fi
}

# ── JSON helpers ─────────────────────────────────────────────
validate_json() {
  local file="$1"
  if [[ "$JSON_PARSE_MODE" == "jq" ]]; then
    jq empty "$file" 2>/dev/null || die "Invalid JSON in: $file"
  else
    $PYTHON_BIN -c "import json; json.load(open('$file'))" 2>/dev/null \
      || die "Invalid JSON in: $file"
  fi
}

get_count() {
  if [[ "$JSON_PARSE_MODE" == "jq" ]]; then
    jq '.presets | length' "$CONFIG_FILE"
  else
    $PYTHON_BIN -c "import json,sys;d=json.load(open(sys.argv[1]));print(len(d.get('presets',[])))" "$CONFIG_FILE"
  fi
}

get_name() { local i="$1"
  if [[ "$JSON_PARSE_MODE" == "jq" ]]; then
    jq -r ".presets[$i].name // \"(unnamed)\"" "$CONFIG_FILE"
  else
    $PYTHON_BIN -c "import json,sys;d=json.load(open(sys.argv[1]));p=d['presets'][$i];print(p.get('name','(unnamed)'))" "$CONFIG_FILE"
  fi
}

get_env() { local i="$1"
  if [[ "$JSON_PARSE_MODE" == "jq" ]]; then
    jq -r ".presets[$i].env | to_entries[] | \"\(.key)=\(.value)\"" "$CONFIG_FILE"
  else
    $PYTHON_BIN -c "
import json,sys
d=json.load(open(sys.argv[1]))
env=d['presets'][$i].get('env',{})
for k,v in env.items(): print(f'{k}={v}')
" "$CONFIG_FILE"
  fi
}

get_field() { local i="$1" f="$2"
  if [[ "$JSON_PARSE_MODE" == "jq" ]]; then
    jq -r ".presets[$i].env.\"$f\" // \"\"" "$CONFIG_FILE"
  else
    $PYTHON_BIN -c "import json,sys;d=json.load(open(sys.argv[1]));print(d['presets'][$i].get('env',{}).get('$f',''))" "$CONFIG_FILE"
  fi
}

get_description() { local i="$1"
  if [[ "$JSON_PARSE_MODE" == "jq" ]]; then
    jq -r ".presets[$i].description // \"\"" "$CONFIG_FILE"
  else
    $PYTHON_BIN -c "import json,sys;d=json.load(open(sys.argv[1]));print(d['presets'][$i].get('description',''))" "$CONFIG_FILE"
  fi
}

# ── Config validation ────────────────────────────────────────
validate_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    die "Config not found: $CONFIG_FILE. Run: claude-launcher install"
  fi
  if [[ ! -r "$CONFIG_FILE" ]]; then
    die "Cannot read: $CONFIG_FILE"
  fi
  validate_json "$CONFIG_FILE"
}

check_permissions() {
  if find "$CONFIG_FILE" -perm -o+r -maxdepth 0 2>/dev/null | grep -q .; then
    warn "Config file is world-readable (contains API tokens)."
    printf "  ${YELLOW}Fix:${NC} chmod 600 \"%s\"\n" "$CONFIG_FILE" >&2
    printf "  ${YELLOW}Fix now? [y/N]:${NC} " >&2
    read -r ans
    [[ "$ans" == "y" || "$ans" == "Y" ]] && chmod 600 "$CONFIG_FILE" \
      && printf "${GREEN}Permissions updated.${NC}\n" >&2
  fi
}

check_required_fields() {
  local count errors preset_name base_url auth_token
  count=$(get_count)
  errors=""

  if [[ "$JSON_PARSE_MODE" == "jq" ]]; then
    errors=$(jq -r '.presets | to_entries[] |
      (if (.value.name // "") == "" then "  Preset #\(.key+1): missing \"name\"" else empty end),
      (if (.value.env | type) != "object" or (.value.env // {}) == {} then "  Preset \"\(.value.name // "unnamed")\": missing \"env\"" else empty end)
    ' "$CONFIG_FILE")
    if [[ -n "$errors" ]]; then
      printf "${RED}Validation errors:${NC}\n%s\n" "$errors" >&2; exit 1
    fi
    for ((i=0; i<count; i++)); do
      preset_name=$(jq -r ".presets[$i].name" "$CONFIG_FILE")
      base_url=$(jq -r ".presets[$i].env.ANTHROPIC_BASE_URL // \"\"" "$CONFIG_FILE")
      auth_token=$(jq -r ".presets[$i].env.ANTHROPIC_AUTH_TOKEN // \"\"" "$CONFIG_FILE")
      [[ -z "$base_url" ]] && warn "Preset \"$preset_name\": ANTHROPIC_BASE_URL is empty"
      [[ -z "$auth_token" ]] && warn "Preset \"$preset_name\": ANTHROPIC_AUTH_TOKEN is empty"
    done
  else
    errors=$($PYTHON_BIN -c "
import json,sys
d=json.load(open(sys.argv[1]))
errs=[]
for i,p in enumerate(d.get('presets',[])):
    if not p.get('name'): errs.append(f'  Preset #{i+1}: missing \"name\"')
    env=p.get('env')
    if not isinstance(env,dict) or len(env)==0: errs.append(f'  Preset \"{p.get(\"name\",\"unnamed\")}\": missing \"env\"')
if errs: print('\\n'.join(errs))
" "$CONFIG_FILE")
    if [[ -n "$errors" ]]; then
      printf "${RED}Validation errors:${NC}\n%s\n" "$errors" >&2; exit 1
    fi
    for ((i=0; i<count; i++)); do
      preset_name=$($PYTHON_BIN -c "import json,sys;d=json.load(open(sys.argv[1]));print(d['presets'][$i]['name'])" "$CONFIG_FILE")
      base_url=$(get_field "$i" "ANTHROPIC_BASE_URL")
      auth_token=$(get_field "$i" "ANTHROPIC_AUTH_TOKEN")
      [[ -z "$base_url" ]] && warn "Preset \"$preset_name\": ANTHROPIC_BASE_URL is empty"
      [[ -z "$auth_token" ]] && warn "Preset \"$preset_name\": ANTHROPIC_AUTH_TOKEN is empty"
    done
  fi
}

# ==============================================================
#  LAUNCH MODE
# ==============================================================
launch_mode() {
  local count
  count=$(get_count)
  if [[ "$count" -eq 0 ]]; then
    die "No presets found. Run: claude-launcher models to add one."
  fi

  printf "\n${BOLD}${BLUE}Claude Launcher${NC} ${VERSION}\n\n"
  for ((i=0; i<count; i++)); do
    printf "  ${BOLD}%2d)${NC} %s\n" $((i+1)) "$(get_name "$i")"
  done
  printf "\n  ${BOLD} q)${NC} Quit\n\n"

  while true; do
    printf "Enter choice [1-%d]: " "$count"
    read -r choice
    [[ "$choice" == "q" || "$choice" == "Q" ]] && exit 0
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
      break
    fi
    printf "${RED}Invalid.${NC} Enter 1-%d or q.\n" "$count"
  done

  local selected_name
  selected_name=$(get_name $((choice-1)))
  printf "\n${GREEN}Starting with \"%s\"...${NC}\n\n" "$selected_name"
  while IFS='=' read -r key value; do
    export "$key"="$value"
  done < <(get_env $((choice-1)))
  exec claude "$@"
}

# ==============================================================
#  MODELS MANAGEMENT
# ==============================================================
models_menu() {
  printf "\n${BOLD}${BLUE}Model Management${NC}\n\n"
  printf "  ${BOLD}1)${NC} List\n"
  printf "  ${BOLD}2)${NC} Add\n"
  printf "  ${BOLD}3)${NC} Edit\n"
  printf "  ${BOLD}4)${NC} Remove\n"
  printf "  ${BOLD}q)${NC} Back\n\n"
  printf "Choice: "
  read -r action
  case "$action" in
    1) list_presets ;;
    2) add_preset ;;
    3) edit_preset ;;
    4) remove_preset ;;
    q|Q) return 0 ;;
    *) printf "${RED}Invalid choice.${NC}\n"; return 1 ;;
  esac
}

list_presets() {
  local count
  count=$(get_count)
  printf "\n${BOLD}Presets:${NC}\n\n"
  if [[ "$count" -eq 0 ]]; then
    printf "  ${YELLOW}(none)${NC}\n"; return
  fi
  for ((i=0; i<count; i++)); do
    local name desc token base_url model masked
    name=$(get_name "$i")
    desc=$(get_description "$i")
    base_url=$(get_field "$i" "ANTHROPIC_BASE_URL")
    token=$(get_field "$i" "ANTHROPIC_AUTH_TOKEN")
    model=$(get_field "$i" "ANTHROPIC_MODEL")
    masked="(empty)"
    if [[ -n "$token" ]]; then
      if [[ ${#token} -gt 8 ]]; then
        masked="${token:0:4}****${token: -4}"
      else
        masked="${token:0:1}****"
      fi
    fi
    printf "  ${BOLD}%d)${NC} %s\n" $((i+1)) "$name"
    [[ -n "$desc" ]] && printf "     %s\n" "$desc"
    printf "     %-14s %s\n" "Base URL:" "$base_url"
    printf "     %-14s %s\n" "Token:" "$masked"
    printf "     %-14s %s\n" "Model:" "$model"
    echo ""
  done
}

add_preset() {
  local name desc base_url token model small_fast sonnet opus haiku disable_traffic
  printf "\n${BOLD}Add New Preset${NC}\n"
  printf "───────────────\n"

  while true; do
    printf "Name: "; read -r name
    [[ -n "$name" ]] && break
    printf "${RED}Name is required.${NC}\n"
  done

  printf "Description (optional): "; read -r desc
  printf "API Base URL [https://api.anthropic.com]: "; read -r base_url
  base_url="${base_url:-https://api.anthropic.com}"
  printf "Auth Token: "; read -r token

  printf "Default model: "; read -r model
  while [[ -z "$model" ]]; do
    printf "${RED}Model is required.${NC} Default model: "; read -r model
  done

  printf "Small/Fast model [%s]: " "$model"; read -r small_fast; small_fast="${small_fast:-$model}"
  printf "Sonnet model [%s]: " "$model"; read -r sonnet; sonnet="${sonnet:-$model}"
  printf "Opus model [%s]: " "$model"; read -r opus; opus="${opus:-$model}"
  printf "Haiku model [%s]: " "$model"; read -r haiku; haiku="${haiku:-$model}"
  printf "Disable non-essential traffic? [y/N]: "; read -r disable_traffic
  disable_traffic="${disable_traffic:-n}"

  # Custom env vars
  printf "Add custom env vars? (KEY=VALUE, empty to finish):\n"
  local custom_keys=() custom_vals=()
  while true; do
    printf "  > "; read -r line
    [[ -z "$line" ]] && break
    if [[ "$line" != *"="* ]]; then
      printf "  ${RED}Must be KEY=VALUE format.${NC}\n"; continue
    fi
    custom_keys+=("${line%%=*}"); custom_vals+=("${line#*=}")
  done

  local tmpfile extra_json=""
  tmpfile=$(mktemp "${CONFIG_FILE}.XXXXXX")

  if [[ "$JSON_PARSE_MODE" == "jq" ]]; then
    [[ "$disable_traffic" =~ ^[yY] ]] && extra_json='"CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"'
    for ((idx=0; idx<${#custom_keys[@]}; idx++)); do
      [[ -n "$extra_json" ]] && extra_json="$extra_json, "
      extra_json="$extra_json\"${custom_keys[$idx]}\": \"${custom_vals[$idx]}\""
    done

    local jq_args=(--arg name "$name" --arg base_url "$base_url" --arg token "$token"
                   --arg model "$model" --arg small_fast "$small_fast" --arg sonnet "$sonnet"
                   --arg opus "$opus" --arg haiku "$haiku")
    [[ -n "$desc" ]] && jq_args+=(--arg description "$desc")

    if [[ -n "$desc" ]]; then
      jq "${jq_args[@]}" ".presets += [{
        name: \$name, description: \$description,
        env: { ANTHROPIC_BASE_URL: \$base_url, ANTHROPIC_AUTH_TOKEN: \$token,
          ANTHROPIC_MODEL: \$model, ANTHROPIC_SMALL_FAST_MODEL: \$small_fast,
          ANTHROPIC_DEFAULT_SONNET_MODEL: \$sonnet, ANTHROPIC_DEFAULT_OPUS_MODEL: \$opus,
          ANTHROPIC_DEFAULT_HAIKU_MODEL: \$haiku ${extra_json:+, $extra_json} }
      }]" "$CONFIG_FILE" > "$tmpfile"
    else
      jq "${jq_args[@]}" ".presets += [{
        name: \$name,
        env: { ANTHROPIC_BASE_URL: \$base_url, ANTHROPIC_AUTH_TOKEN: \$token,
          ANTHROPIC_MODEL: \$model, ANTHROPIC_SMALL_FAST_MODEL: \$small_fast,
          ANTHROPIC_DEFAULT_SONNET_MODEL: \$sonnet, ANTHROPIC_DEFAULT_OPUS_MODEL: \$opus,
          ANTHROPIC_DEFAULT_HAIKU_MODEL: \$haiku ${extra_json:+, $extra_json} }
      }]" "$CONFIG_FILE" > "$tmpfile"
    fi
  else
    local py_add_custom=""
    for ((idx=0; idx<${#custom_keys[@]}; idx++)); do
      py_add_custom="$py_add_custom"'preset[env]["'${custom_keys[$idx]}'"]='"'${custom_vals[$idx]}'"'; '
    done
    $PYTHON_BIN -c "
import json,sys
d=json.load(open(sys.argv[1]))
preset={'name':sys.argv[2]}
desc=sys.argv[3]
if desc: preset['description']=desc
env={'ANTHROPIC_BASE_URL':sys.argv[4],'ANTHROPIC_AUTH_TOKEN':sys.argv[5],
  'ANTHROPIC_MODEL':sys.argv[6],'ANTHROPIC_SMALL_FAST_MODEL':sys.argv[7],
  'ANTHROPIC_DEFAULT_SONNET_MODEL':sys.argv[8],'ANTHROPIC_DEFAULT_OPUS_MODEL':sys.argv[9],
  'ANTHROPIC_DEFAULT_HAIKU_MODEL':sys.argv[10]}
if sys.argv[11].lower()=='y': env['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC']='1'
exec(sys.argv[12])
preset['env']=env
d['presets'].append(preset)
json.dump(d,open(sys.argv[13],'w'),indent=2)
" "$CONFIG_FILE" "$name" "$desc" "$base_url" "$token" "$model" \
  "$small_fast" "$sonnet" "$opus" "$haiku" "$disable_traffic" "$py_add_custom" "$tmpfile"
  fi

  validate_json "$tmpfile"
  mv "$tmpfile" "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
  printf "${GREEN}Preset \"%s\" added.${NC}\n" "$name"
}

edit_preset() {
  local count
  count=$(get_count)
  if [[ "$count" -eq 0 ]]; then
    printf "${YELLOW}No presets to edit.${NC}\n"; return
  fi

  printf "\n${BOLD}Edit Preset${NC}\n"
  for ((i=0; i<count; i++)); do
    printf "  ${BOLD}%d)${NC} %s\n" $((i+1)) "$(get_name "$i")"
  done
  printf "  q) Cancel\nChoice: "
  read -r pick
  [[ "$pick" == "q" || "$pick" == "Q" ]] && return
  if [[ ! "$pick" =~ ^[0-9]+$ ]] || (( pick < 1 || pick > count )); then
    printf "${RED}Invalid.${NC}\n"; return
  fi
  local idx=$((pick-1))

  local name desc base_url token model small_fast sonnet opus haiku disable
  name=$(get_name "$idx"); desc=$(get_description "$idx")
  base_url=$(get_field "$idx" "ANTHROPIC_BASE_URL")
  token=$(get_field "$idx" "ANTHROPIC_AUTH_TOKEN")
  model=$(get_field "$idx" "ANTHROPIC_MODEL")
  small_fast=$(get_field "$idx" "ANTHROPIC_SMALL_FAST_MODEL")
  sonnet=$(get_field "$idx" "ANTHROPIC_DEFAULT_SONNET_MODEL")
  opus=$(get_field "$idx" "ANTHROPIC_DEFAULT_OPUS_MODEL")
  haiku=$(get_field "$idx" "ANTHROPIC_DEFAULT_HAIKU_MODEL")
  disable=$(get_field "$idx" "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC")

  while true; do
    local dt_label="off"; [[ "$disable" == "1" ]] && dt_label="on"
    local masked_token="(empty)"
    [[ -n "$token" ]] && masked_token="${token:0:4}...${token: -4}"

    printf "\n${BOLD}Editing: %s${NC}\n" "$name"
    printf "  ${BOLD}1)${NC} Name:        %s\n" "$name"
    printf "  ${BOLD}2)${NC} Description: %s\n" "$desc"
    printf "  ${BOLD}3)${NC} Base URL:    %s\n" "$base_url"
    printf "  ${BOLD}4)${NC} Auth Token:  %s\n" "$masked_token"
    printf "  ${BOLD}5)${NC} Model:       %s\n" "$model"
    printf "  ${BOLD}6)${NC} Small/Fast:  %s\n" "$small_fast"
    printf "  ${BOLD}7)${NC} Sonnet:      %s\n" "$sonnet"
    printf "  ${BOLD}8)${NC} Opus:        %s\n" "$opus"
    printf "  ${BOLD}9)${NC} Haiku:       %s\n" "$haiku"
    printf "  ${BOLD}0)${NC} No-essent:   %s\n" "$dt_label"
    printf "  ${BOLD}s)${NC} Save & done\n"
    printf "  ${BOLD}q)${NC} Cancel\n"
    printf "Choice: "
    read -r field_choice
    local v

    case "$field_choice" in
      1) printf "New name [%s]: " "$name"; read -r v; [[ -n "$v" ]] && name="$v" ;;
      2) printf "New description [%s]: " "$desc"; read -r v; desc="$v" ;;
      3) printf "New base URL [%s]: " "$base_url"; read -r v; [[ -n "$v" ]] && base_url="$v" ;;
      4) printf "New token [%s]: " "$masked_token"; read -r v; [[ -n "$v" ]] && token="$v" ;;
      5) printf "New model [%s]: " "$model"; read -r v; [[ -n "$v" ]] && model="$v" ;;
      6) printf "New small/fast [%s]: " "$small_fast"; read -r v; [[ -n "$v" ]] && small_fast="$v" ;;
      7) printf "New sonnet [%s]: " "$sonnet"; read -r v; [[ -n "$v" ]] && sonnet="$v" ;;
      8) printf "New opus [%s]: " "$opus"; read -r v; [[ -n "$v" ]] && opus="$v" ;;
      9) printf "New haiku [%s]: " "$haiku"; read -r v; [[ -n "$v" ]] && haiku="$v" ;;
      0) printf "Toggle non-essential traffic [y/N]: "; read -r v
          [[ "$v" =~ ^[yY] ]] && disable="1" || disable="" ;;
      s|S)
        local tmpfile; tmpfile=$(mktemp "${CONFIG_FILE}.XXXXXX")
        if [[ "$JSON_PARSE_MODE" == "jq" ]]; then
          local jq_expr=".presets[$idx].name = \$name"
          jq_expr="$jq_expr | .presets[$idx].env.ANTHROPIC_BASE_URL = \$base_url"
          jq_expr="$jq_expr | .presets[$idx].env.ANTHROPIC_AUTH_TOKEN = \$token"
          jq_expr="$jq_expr | .presets[$idx].env.ANTHROPIC_MODEL = \$model"
          jq_expr="$jq_expr | .presets[$idx].env.ANTHROPIC_SMALL_FAST_MODEL = \$small_fast"
          jq_expr="$jq_expr | .presets[$idx].env.ANTHROPIC_DEFAULT_SONNET_MODEL = \$sonnet"
          jq_expr="$jq_expr | .presets[$idx].env.ANTHROPIC_DEFAULT_OPUS_MODEL = \$opus"
          jq_expr="$jq_expr | .presets[$idx].env.ANTHROPIC_DEFAULT_HAIKU_MODEL = \$haiku"
          if [[ -n "$disable" ]]; then
            jq_expr="$jq_expr | .presets[$idx].env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = \"1\""
          else
            jq_expr="$jq_expr | del(.presets[$idx].env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC)"
          fi
          local extra_jq_args=()
          if [[ -n "$desc" ]]; then
            jq_expr="$jq_expr | .presets[$idx].description = \$description"
            extra_jq_args+=(--arg description "$desc")
          else
            jq_expr="$jq_expr | del(.presets[$idx].description)"
          fi
          jq --arg name "$name" --arg base_url "$base_url" --arg token "$token" \
             --arg model "$model" --arg small_fast "$small_fast" --arg sonnet "$sonnet" \
             --arg opus "$opus" --arg haiku "$haiku" "${extra_jq_args[@]}" \
             "$jq_expr" "$CONFIG_FILE" > "$tmpfile"
        else
          $PYTHON_BIN -c "
import json,sys
d=json.load(open(sys.argv[1])); p=d['presets'][int(sys.argv[2])]
p['name']=sys.argv[3]
if sys.argv[4]: p['description']=sys.argv[4]
elif 'description' in p: del p['description']
e=p['env']
e['ANTHROPIC_BASE_URL']=sys.argv[5]; e['ANTHROPIC_AUTH_TOKEN']=sys.argv[6]
e['ANTHROPIC_MODEL']=sys.argv[7]; e['ANTHROPIC_SMALL_FAST_MODEL']=sys.argv[8]
e['ANTHROPIC_DEFAULT_SONNET_MODEL']=sys.argv[9]; e['ANTHROPIC_DEFAULT_OPUS_MODEL']=sys.argv[10]
e['ANTHROPIC_DEFAULT_HAIKU_MODEL']=sys.argv[11]
if sys.argv[12]=='1': e['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC']='1'
elif 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC' in e: del e['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC']
json.dump(d,open(sys.argv[13],'w'),indent=2)
" "$CONFIG_FILE" "$idx" "$name" "$desc" "$base_url" "$token" "$model" \
  "$small_fast" "$sonnet" "$opus" "$haiku" "${disable:-0}" "$tmpfile"
        fi
        validate_json "$tmpfile"; mv "$tmpfile" "$CONFIG_FILE"; chmod 600 "$CONFIG_FILE"
        printf "${GREEN}Saved.${NC}\n"; return
        ;;
      q|Q) return ;;
      *) printf "${RED}Invalid choice.${NC}\n" ;;
    esac
  done
}

remove_preset() {
  local count
  count=$(get_count)
  if [[ "$count" -eq 0 ]]; then
    printf "${YELLOW}No presets to remove.${NC}\n"; return
  fi

  printf "\n${BOLD}Remove Preset${NC}\n"
  for ((i=0; i<count; i++)); do
    printf "  ${BOLD}%d)${NC} %s\n" $((i+1)) "$(get_name "$i")"
  done
  printf "  q) Cancel\nChoice: "
  read -r pick
  [[ "$pick" == "q" || "$pick" == "Q" ]] && return
  if [[ ! "$pick" =~ ^[0-9]+$ ]] || (( pick < 1 || pick > count )); then
    printf "${RED}Invalid.${NC}\n"; return
  fi
  local idx=$((pick-1))
  local preset_name; preset_name=$(get_name "$idx")

  [[ "$count" -eq 1 ]] && printf "${YELLOW}This is the last preset.${NC}\n"
  printf "Delete \"${RED}%s${NC}\"? This cannot be undone. [y/N]: " "$preset_name"
  read -r confirm
  [[ ! "$confirm" =~ ^[yY] ]] && { printf "Cancelled.\n"; return; }

  local tmpfile; tmpfile=$(mktemp "${CONFIG_FILE}.XXXXXX")
  if [[ "$JSON_PARSE_MODE" == "jq" ]]; then
    jq "del(.presets[$idx])" "$CONFIG_FILE" > "$tmpfile"
  else
    $PYTHON_BIN -c "
import json,sys
d=json.load(open(sys.argv[1])); d['presets'].pop($idx)
json.dump(d,open(sys.argv[2],'w'),indent=2)
" "$CONFIG_FILE" "$tmpfile"
  fi
  validate_json "$tmpfile"; mv "$tmpfile" "$CONFIG_FILE"; chmod 600 "$CONFIG_FILE"
  printf "${GREEN}\"%s\" removed.${NC}\n" "$preset_name"
}

# ==============================================================
#  INSTALL MODE
# ==============================================================
install_mode() {
  local INSTALL_DIR="$HOME/.config/claude-launcher"
  local LAUNCHER="$INSTALL_DIR/claude-launcher"
  local CONFIG_FILE="$INSTALL_DIR/presets.json"
  local SELF
  SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

  printf "${BOLD}${BLUE}Claude Launcher v${VERSION} - Installer${NC}\n\n"

  mkdir -p "$INSTALL_DIR"

  # Template config
  if [[ -f "$CONFIG_FILE" ]]; then
    printf "→ presets.json already exists, skipping\n"
  else
    cat > "$CONFIG_FILE" << 'PRESETS'
{
  "version": "1",
  "presets": [
    {
      "name": "Anthropic (Native)",
      "description": "Direct Anthropic API with Claude models",
      "env": {
        "ANTHROPIC_BASE_URL": "https://api.anthropic.com",
        "ANTHROPIC_AUTH_TOKEN": "YOUR_ANTHROPIC_API_KEY",
        "ANTHROPIC_MODEL": "claude-sonnet-4-20250514",
        "ANTHROPIC_SMALL_FAST_MODEL": "claude-sonnet-4-20250514",
        "ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-sonnet-4-20250514",
        "ANTHROPIC_DEFAULT_OPUS_MODEL": "claude-opus-4-20250514",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL": "claude-haiku-3-5-20241022"
      }
    }
  ]
}
PRESETS
    printf "→ Template presets.json created\n"
  fi
  chmod 600 "$CONFIG_FILE"

  # Copy self as launcher
  cp "$SELF" "$LAUNCHER"
  chmod +x "$LAUNCHER"
  printf "→ Launcher installed to %s\n" "$LAUNCHER"

  # ── Detect platform ─────────────────────────────────────
  local OS=""
  case "$(uname -s)" in
    Darwin)  OS="macos" ;;
    Linux)   OS="linux" ;;
  esac

  # ── Check and install prerequisites ─────────────────────
  printf "\n${BOLD}Checking prerequisites...${NC}\n\n"

  local need_jq=0 need_claude=0 need_bash=0

  # jq
  if command -v jq &>/dev/null; then
    printf "  ✓ jq: %s\n" "$(command -v jq)"
  elif command -v python3 &>/dev/null; then
    printf "  ✓ python3 (JSON fallback): %s\n" "$(command -v python3)"
  elif command -v python &>/dev/null; then
    printf "  ✓ python (JSON fallback): %s\n" "$(command -v python)"
  else
    printf "  ✗ jq not found\n"
    need_jq=1
  fi

  # claude CLI
  if command -v claude &>/dev/null; then
    printf "  ✓ claude CLI: %s\n" "$(command -v claude)"
  else
    printf "  ✗ claude CLI not found\n"
    need_claude=1
  fi

  # bash 4+ (optional, but recommended)
  local bash_ver=0
  if command -v bash &>/dev/null; then
    bash_ver=$(bash --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d. -f1)
  fi
  if [[ "$bash_ver" -ge 4 ]]; then
    printf "  ✓ bash: %s\n" "$(bash --version | head -1)"
  else
    printf "  ○ bash 4+ not detected (zsh is fine too)\n"
    need_bash=1
  fi

  # Auto-install missing components
  if [[ "$need_jq" -eq 1 || "$need_bash" -eq 1 ]]; then
    printf "\n${YELLOW}Missing components detected.${NC}\n"
    printf "Auto-install? [Y/n]: "
    read -r do_install
    [[ "$do_install" == "n" || "$do_install" == "N" ]] && do_install="n" || do_install="y"

    if [[ "$do_install" == "y" ]]; then
      if [[ "$need_jq" -eq 1 ]]; then
        printf "Installing jq..."
        case "$OS" in
          macos)
            if command -v brew &>/dev/null; then
              brew install jq &>/dev/null && printf " done\n" || printf " failed — install manually: brew install jq\n"
            else
              printf " skipped (Homebrew not found)\n"
            fi
            ;;
          linux)
            if command -v apt-get &>/dev/null; then
              sudo apt-get update -qq && sudo apt-get install -y -qq jq &>/dev/null && printf " done\n" || printf " failed\n"
            elif command -v yum &>/dev/null; then
              sudo yum install -y -q jq &>/dev/null && printf " done\n" || printf " failed\n"
            elif command -v dnf &>/dev/null; then
              sudo dnf install -y -q jq &>/dev/null && printf " done\n" || printf " failed\n"
            elif command -v pacman &>/dev/null; then
              sudo pacman -S --noconfirm jq &>/dev/null && printf " done\n" || printf " failed\n"
            elif command -v apk &>/dev/null; then
              sudo apk add jq &>/dev/null && printf " done\n" || printf " failed\n"
            else
              printf " skipped (no supported package manager)\n"
            fi
            ;;
          *) printf " skipped (unknown OS)\n" ;;
        esac
      fi

      if [[ "$need_bash" -eq 1 ]]; then
        printf "Installing bash 4+..."
        case "$OS" in
          macos)
            if command -v brew &>/dev/null; then
              brew install bash &>/dev/null && printf " done\n" || printf " failed\n"
            fi
            ;;
          linux)
            if command -v apt-get &>/dev/null; then
              sudo apt-get install -y -qq bash &>/dev/null && printf " done\n" || printf " failed\n"
            elif command -v yum &>/dev/null; then
              sudo yum install -y -q bash &>/dev/null && printf " done\n" || printf " failed\n"
            fi
            ;;
        esac
      fi
    fi
  fi

  # claude CLI install hint
  if [[ "$need_claude" -eq 1 ]]; then
    printf "\n${YELLOW}claude CLI not found.${NC} Install it:\n"
    case "$OS" in
      macos) printf "  brew install claude-code\n" ;;
      linux) printf "  npm install -g @anthropic-ai/claude-code\n" ;;
    esac
  fi

  # Add alias to shell rc
  local marker="# claude-launcher"
  local alias_line="alias claude-launcher=\"$LAUNCHER\"  $marker"

  case "${SHELL##*/}" in
    zsh)  local rc="$HOME/.zshrc" ;;
    bash) local rc="$HOME/.bashrc"
          [[ -f "$HOME/.bash_profile" ]] && rc="$HOME/.bash_profile" ;;
    *)    local rc=""
  esac

  if [[ -n "$rc" ]]; then
    if grep -qF "$marker" "$rc" 2>/dev/null; then
      printf "→ alias already in %s\n" "$rc"
    else
      printf '\n%s\n' "$alias_line" >> "$rc"
      printf "→ alias added to %s\n" "$rc"
    fi
  fi

  printf "\n${GREEN}Done.${NC} Run: ${BOLD}claude-launcher${NC}"
  [[ -z "$rc" ]] && printf "  (or %s)" "$LAUNCHER"
  printf "\nEdit presets: %s\n" "$CONFIG_FILE"
}

# ==============================================================
#  UNINSTALL MODE
# ==============================================================
uninstall_mode() {
  printf "${RED}${BOLD}Uninstall Claude Launcher${NC}\n\n"
  printf "This will delete %s and remove shell alias.\n\n" "$HOME/.config/claude-launcher/"
  printf "${RED}Continue? [y/N]:${NC} "
  read -r confirm
  [[ ! "$confirm" =~ ^[yY] ]] && { printf "Cancelled.\n"; exit 0; }

  printf "\nRemoving config directory...\n"
  rm -rf "$HOME/.config/claude-launcher" \
    && printf "  ${GREEN}Deleted${NC} %s\n" "$HOME/.config/claude-launcher/" \
    || printf "  ${YELLOW}Failed${NC} — remove manually: rm -rf %s\n" "$HOME/.config/claude-launcher/"

  printf "Removing shell alias...\n"
  local marker="# claude-launcher" removed=0
  for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
    if [[ -f "$rc" ]] && grep -qF "$marker" "$rc" 2>/dev/null; then
      if [[ "$(uname -s)" == "Darwin" ]]; then
        sed -i '' "/$marker/d" "$rc"
      else
        sed -i "/$marker/d" "$rc"
      fi
      printf "  ${GREEN}Removed${NC} from %s\n" "$rc"; removed=1
    fi
  done
  [[ "$removed" -eq 0 ]] && printf "  ${YELLOW}No alias found.${NC}\n"

  printf "\n${GREEN}Claude Launcher uninstalled.${NC} Restart your shell.\n"
  exit 0
}

# ==============================================================
#  MAIN — Command dispatch
# ==============================================================

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  show_help; exit 0
fi

# Auto-detect install: named install.sh, first arg is "install", or piped via curl|bash
if [[ "$SCRIPT_NAME" == "install"* ]] || [[ "$SCRIPT_NAME" == "install.sh" ]] \
   || [[ "${1:-}" == "install" ]] \
   || [[ ( "$SCRIPT_NAME" == "bash" || "$SCRIPT_NAME" == "-bash" || "$SCRIPT_NAME" == "sh" ) && -z "${1:-}" ]]; then
  [[ "${1:-}" == "install" ]] && shift || true
  install_mode
  exit 0
fi

COMMAND="${1:-launch}"

# If first arg starts with '-' and isn't -h/--help, it's a claude flag — route to launch
if [[ "$COMMAND" == -* ]]; then
  COMMAND="launch"
else
  shift || true
fi

case "$COMMAND" in
  launch)
    resolve_config; detect_parser; validate_config
    check_required_fields; check_permissions
    launch_mode "$@"
    ;;
  models)
    resolve_config; detect_parser; validate_config
    check_required_fields
    models_menu
    ;;
  uninstall)
    uninstall_mode
    ;;
  *)
    # Unknown non-flag: pass through as claude args in launch mode
    set -- "$COMMAND" "$@"
    resolve_config; detect_parser; validate_config
    check_required_fields; check_permissions
    launch_mode "$@"
    ;;
esac
