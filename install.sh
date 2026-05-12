#!/usr/bin/env bash
set -uo pipefail

VERSION="1.0.0"

# ── Color support ────────────────────────────────────────────
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]] && [[ -z "${CLAUDE_LAUNCHER_NO_COLOR:-}" ]]; then
  RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m'
  BLUE='\033[0;34m' BOLD='\033[1m' NC='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' BOLD='' NC=''
fi

die() { printf "${RED}Error:${NC} %s\n" "$1" >&2; exit 1; }
warn() { printf "${YELLOW}Warning:${NC} %s\n" "$1" >&2; }

# ── Install mode ─────────────────────────────────────────────
INSTALL_DIR="$HOME/.config/claude-launcher"
LAUNCHER="$INSTALL_DIR/claude-launcher"
CONFIG_FILE="$INSTALL_DIR/presets.json"

# Allow custom config path
if [[ -n "${CLAUDE_LAUNCHER_CONFIG:-}" ]]; then
  CONFIG_FILE="$CLAUDE_LAUNCHER_CONFIG"
  [[ "$CONFIG_FILE" != /* ]] && CONFIG_FILE="$(pwd)/$CONFIG_FILE"
  INSTALL_DIR="$(dirname "$CONFIG_FILE")"
  LAUNCHER="$INSTALL_DIR/claude-launcher"
fi

printf "${BOLD}${BLUE}Claude Launcher v${VERSION} - Installer${NC}\n\n"
mkdir -p "$INSTALL_DIR"

# ── Template config ──────────────────────────────────────────
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

# ── Detect platform ──────────────────────────────────────────
OS=""
case "$(uname -s)" in
  Darwin) OS="macos" ;;
  Linux)  OS="linux" ;;
esac

# ── Check and install prerequisites ──────────────────────────
printf "\n${BOLD}Checking prerequisites...${NC}\n\n"

need_jq=0 need_claude=0 need_bash=0

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

# claude
if command -v claude &>/dev/null; then
  printf "  ✓ claude CLI: %s\n" "$(command -v claude)"
else
  printf "  ✗ claude CLI not found\n"
  need_claude=1
fi

# bash 4+
bash_ver=0
if command -v bash &>/dev/null; then
  bash_ver=$(bash --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d. -f1)
fi
if [[ "$bash_ver" -ge 4 ]]; then
  printf "  ✓ bash: %s\n" "$(bash --version | head -1)"
elif [[ -n "$ZSH_VERSION" ]]; then
  printf "  ✓ zsh (shell)\n"
else
  printf "  ○ bash 4+ not detected\n"
  need_bash=1
fi

auto_install() {
  local pkg="$1"
  local label="$2"
  printf "Installing %s..." "$label"
  case "$OS" in
    macos)
      command -v brew &>/dev/null && brew install "$pkg" &>/dev/null && { printf " done\n"; return 0; }
      ;;
    linux)
      if command -v apt-get &>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y -qq "$pkg" &>/dev/null && { printf " done\n"; return 0; }
      elif command -v yum &>/dev/null; then
        sudo yum install -y -q "$pkg" &>/dev/null && { printf " done\n"; return 0; }
      elif command -v dnf &>/dev/null; then
        sudo dnf install -y -q "$pkg" &>/dev/null && { printf " done\n"; return 0; }
      elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm "$pkg" &>/dev/null && { printf " done\n"; return 0; }
      elif command -v apk &>/dev/null; then
        sudo apk add "$pkg" &>/dev/null && { printf " done\n"; return 0; }
      fi
      ;;
  esac
  printf " failed (install manually)\n"
  return 1
}

if [[ "$need_jq" -eq 1 || "$need_bash" -eq 1 ]]; then
  printf "\n${YELLOW}Missing components detected.${NC}\n"
  printf "Auto-install? [Y/n]: "
  read -r do_install
  [[ "$do_install" == "n" || "$do_install" == "N" ]] && do_install="n" || do_install="y"
  if [[ "$do_install" == "y" ]]; then
    [[ "$need_jq" -eq 1 ]] && auto_install jq "jq"
    [[ "$need_bash" -eq 1 ]] && auto_install bash "bash 4+"
  fi
fi

if [[ "$need_claude" -eq 1 ]]; then
  printf "\n${YELLOW}claude CLI not found.${NC} Install it:\n"
  case "$OS" in
    macos) printf "  brew install claude-code\n" ;;
    linux) printf "  npm install -g @anthropic-ai/claude-code\n" ;;
  esac
fi

# ── Write launcher script ────────────────────────────────────
cat > "$LAUNCHER" << 'LAUNCHER'
#!/usr/bin/env bash
set -uo pipefail

VERSION="1.0.0"

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]] && [[ -z "${CLAUDE_LAUNCHER_NO_COLOR:-}" ]]; then
  RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m'
  BLUE='\033[0;34m' BOLD='\033[1m' NC='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' BOLD='' NC=''
fi

die() { printf "${RED}Error:${NC} %s\n" "$1" >&2; exit 1; }
warn() { printf "${YELLOW}Warning:${NC} %s\n" "$1" >&2; }

show_help() {
  cat <<'HELP'
Claude Launcher - Switch Claude Code model presets from a menu.

Usage:
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

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then show_help; exit 0; fi

DEFAULT_CONFIG="$HOME/.config/claude-launcher/presets.json"

resolve_config() {
  if [[ -n "${CLAUDE_LAUNCHER_CONFIG:-}" ]]; then
    CONFIG_FILE="$CLAUDE_LAUNCHER_CONFIG"
    [[ "$CONFIG_FILE" != /* ]] && CONFIG_FILE="$(pwd)/$CONFIG_FILE"
  else CONFIG_FILE="$DEFAULT_CONFIG"; fi
}

detect_parser() {
  if command -v jq &>/dev/null; then JSON_PARSE_MODE="jq"
  elif command -v python3 &>/dev/null; then JSON_PARSE_MODE="python"; PYTHON_BIN="python3"
  elif command -v python &>/dev/null; then JSON_PARSE_MODE="python"; PYTHON_BIN="python"
  else die "Neither jq nor python3 found."; fi
}

validate_json() {
  local file="$1"
  if [[ "$JSON_PARSE_MODE" == "jq" ]]; then jq empty "$file" 2>/dev/null || die "Invalid JSON: $file"
  else $PYTHON_BIN -c "import json;json.load(open('$file'))" 2>/dev/null || die "Invalid JSON: $file"; fi
}

get_count() {
  if [[ "$JSON_PARSE_MODE" == "jq" ]]; then jq '.presets|length' "$CONFIG_FILE"
  else $PYTHON_BIN -c "import json,sys;d=json.load(open(sys.argv[1]));print(len(d.get('presets',[])))" "$CONFIG_FILE"; fi
}

get_name() { local i="$1"
  if [[ "$JSON_PARSE_MODE" == "jq" ]]; then jq -r ".presets[$i].name//\"(unnamed)\"" "$CONFIG_FILE"
  else $PYTHON_BIN -c "import json,sys;d=json.load(open(sys.argv[1]));p=d['presets'][$i];print(p.get('name','(unnamed)'))" "$CONFIG_FILE"; fi
}

get_env() { local i="$1"
  if [[ "$JSON_PARSE_MODE" == "jq" ]]; then jq -r ".presets[$i].env|to_entries[]|\"\(.key)=\(.value)\"" "$CONFIG_FILE"
  else $PYTHON_BIN -c "import json,sys;d=json.load(open(sys.argv[1]));env=d['presets'][$i].get('env',{});[print(f'{k}={v}') for k,v in env.items()]" "$CONFIG_FILE"; fi
}

get_field() { local i="$1" f="$2"
  if [[ "$JSON_PARSE_MODE" == "jq" ]]; then jq -r ".presets[$i].env.\"$f\"//\"\"" "$CONFIG_FILE"
  else $PYTHON_BIN -c "import json,sys;d=json.load(open(sys.argv[1]));print(d['presets'][$i].get('env',{}).get('$f',''))" "$CONFIG_FILE"; fi
}

get_description() { local i="$1"
  if [[ "$JSON_PARSE_MODE" == "jq" ]]; then jq -r ".presets[$i].description//\"\"" "$CONFIG_FILE"
  else $PYTHON_BIN -c "import json,sys;d=json.load(open(sys.argv[1]));print(d['presets'][$i].get('description',''))" "$CONFIG_FILE"; fi
}

validate_config() {
  [[ ! -f "$CONFIG_FILE" ]] && die "Config not found: $CONFIG_FILE."
  [[ ! -r "$CONFIG_FILE" ]] && die "Cannot read: $CONFIG_FILE"
  validate_json "$CONFIG_FILE"
}

check_permissions() {
  if find "$CONFIG_FILE" -perm -o+r -maxdepth 0 2>/dev/null | grep -q .; then
    warn "Config is world-readable."; printf "  ${YELLOW}Fix:${NC} chmod 600 \"$CONFIG_FILE\"\n" >&2
    printf "  ${YELLOW}Fix now? [y/N]:${NC} " >&2; read -r ans
    [[ "$ans" == "y" || "$ans" == "Y" ]] && chmod 600 "$CONFIG_FILE" && printf "${GREEN}Done.${NC}\n" >&2
  fi
}

check_required_fields() {
  local count errors preset_name base_url auth_token; count=$(get_count); errors=""
  if [[ "$JSON_PARSE_MODE" == "jq" ]]; then
    errors=$(jq -r '.presets|to_entries[]|(if(.value.name//"")==""then"  Preset #\(.key+1): missing \"name\""else empty end),(if(.value.env|type)!="object"or(.value.env//{})=={}then"  Preset \"\(.value.name//"unnamed")\": missing \"env\""else empty end)' "$CONFIG_FILE")
    [[ -n "$errors" ]] && { printf "${RED}Validation errors:${NC}\n%s\n" "$errors" >&2; exit 1; }
    for ((i=0;i<count;i++)); do
      preset_name=$(get_name "$i"); base_url=$(get_field "$i" ANTHROPIC_BASE_URL); auth_token=$(get_field "$i" ANTHROPIC_AUTH_TOKEN)
      [[ -z "$base_url" ]] && warn "Preset \"$preset_name\": ANTHROPIC_BASE_URL is empty"
      [[ -z "$auth_token" ]] && warn "Preset \"$preset_name\": ANTHROPIC_AUTH_TOKEN is empty"
    done
  else
    errors=$($PYTHON_BIN -c "import json,sys;d=json.load(open(sys.argv[1]));errs=[];[errs.append(f'  Preset #{i+1}: missing \"name\"') if not p.get('name') else errs.append(f'  Preset \"{p.get(\"name\",\"unnamed\")}\": missing \"env\"') if not isinstance(p.get('env'),dict)or len(p.get('env',{}))==0 else None for i,p in enumerate(d.get('presets',[]))];print('\\n'.join(errs))if errs else None" "$CONFIG_FILE")
    [[ -n "$errors" ]] && { printf "${RED}Validation errors:${NC}\n%s\n" "$errors" >&2; exit 1; }
    for ((i=0;i<count;i++)); do
      preset_name=$(get_name "$i"); base_url=$(get_field "$i" ANTHROPIC_BASE_URL); auth_token=$(get_field "$i" ANTHROPIC_AUTH_TOKEN)
      [[ -z "$base_url" ]] && warn "Preset \"$preset_name\": ANTHROPIC_BASE_URL is empty"
      [[ -z "$auth_token" ]] && warn "Preset \"$preset_name\": ANTHROPIC_AUTH_TOKEN is empty"
    done
  fi
}

launch_mode() {
  local count; count=$(get_count)
  [[ "$count" -eq 0 ]] && die "No presets found. Run: claude-launcher models to add one."
  printf "\n${BOLD}${BLUE}Claude Launcher${NC} ${VERSION}\n\n"
  for ((i=0;i<count;i++)); do printf "  ${BOLD}%2d)${NC} %s\n" $((i+1)) "$(get_name "$i")"; done
  printf "\n  ${BOLD}q)${NC} Quit\n\n"
  while true; do
    printf "Enter choice [1-%d]: " "$count"; read -r choice
    [[ "$choice" == "q" || "$choice" == "Q" ]] && exit 0
    [[ "$choice" =~ ^[0-9]+$ ]] && ((choice>=1&&choice<=count)) && break
    printf "${RED}Invalid.${NC} Enter 1-%d or q.\n" "$count"
  done
  printf "\n${GREEN}Starting with \"%s\"...${NC}\n\n" "$(get_name $((choice-1)))"
  while IFS='=' read -r key value; do export "$key"="$value"; done < <(get_env $((choice-1)))
  exec claude "$@"
}

models_menu() {
  printf "\n${BOLD}${BLUE}Model Management${NC}\n\n"
  printf "  ${BOLD}1)${NC} List\n  ${BOLD}2)${NC} Add\n  ${BOLD}3)${NC} Edit\n  ${BOLD}4)${NC} Remove\n  ${BOLD}q)${NC} Back\n\nChoice: "
  read -r action
  case "$action" in
    1) list_presets;; 2) add_preset;; 3) edit_preset;; 4) remove_preset;; q|Q) return 0;; *) printf "${RED}Invalid.${NC}\n"; return 1;;
  esac
}

list_presets() {
  local count; count=$(get_count)
  printf "\n${BOLD}Presets:${NC}\n\n"
  [[ "$count" -eq 0 ]] && { printf "  ${YELLOW}(none)${NC}\n"; return; }
  for ((i=0;i<count;i++)); do
    local name desc token base_url model masked
    name=$(get_name "$i"); desc=$(get_description "$i"); base_url=$(get_field "$i" ANTHROPIC_BASE_URL)
    token=$(get_field "$i" ANTHROPIC_AUTH_TOKEN); model=$(get_field "$i" ANTHROPIC_MODEL)
    masked="(empty)"
    if [[ -n "$token" ]]; then
      [[ ${#token} -gt 8 ]] && masked="${token:0:4}****${token: -4}" || masked="${token:0:1}****"
    fi
    printf "  ${BOLD}%d)${NC} %s\n" $((i+1)) "$name"
    [[ -n "$desc" ]] && printf "     %s\n" "$desc"
    printf "     %-14s %s\n" "Base URL:" "$base_url" "Token:" "$masked" "Model:" "$model"
    echo ""
  done
}

add_preset() {
  local name desc base_url token model small_fast sonnet opus haiku disable_traffic
  printf "\n${BOLD}Add New Preset${NC}\n───────────────\n"
  while true; do printf "Name: "; read -r name; [[ -n "$name" ]] && break; printf "${RED}Name required.${NC}\n"; done
  printf "Description (optional): "; read -r desc
  printf "API Base URL [https://api.anthropic.com]: "; read -r base_url; base_url="${base_url:-https://api.anthropic.com}"
  printf "Auth Token: "; read -r token
  printf "Default model: "; read -r model
  while [[ -z "$model" ]]; do printf "${RED}Model required.${NC} Default model: "; read -r model; done
  printf "Small/Fast [%s]: " "$model"; read -r small_fast; small_fast="${small_fast:-$model}"
  printf "Sonnet [%s]: " "$model"; read -r sonnet; sonnet="${sonnet:-$model}"
  printf "Opus [%s]: " "$model"; read -r opus; opus="${opus:-$model}"
  printf "Haiku [%s]: " "$model"; read -r haiku; haiku="${haiku:-$model}"
  printf "Disable non-essential? [y/N]: "; read -r disable_traffic; disable_traffic="${disable_traffic:-n}"
  printf "Custom env vars? (KEY=VALUE, empty to finish):\n"
  local custom_keys=() custom_vals=()
  while true; do printf "  > "; read -r line; [[ -z "$line" ]] && break
    [[ "$line" != *"="* ]] && { printf "  ${RED}Must be KEY=VALUE.${NC}\n"; continue; }
    custom_keys+=("${line%%=*}"); custom_vals+=("${line#*=}")
  done
  local tmpfile extra_json=""; tmpfile=$(mktemp "${CONFIG_FILE}.XXXXXX")
  if [[ "$JSON_PARSE_MODE" == "jq" ]]; then
    [[ "$disable_traffic" =~ ^[yY] ]] && extra_json='"CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC":"1"'
    for ((idx=0;idx<${#custom_keys[@]};idx++)); do
      [[ -n "$extra_json" ]] && extra_json="$extra_json,"
      extra_json="$extra_json\"${custom_keys[$idx]}\":\"${custom_vals[$idx]}\""
    done
    local jq_args=(--arg name "$name" --arg base_url "$base_url" --arg token "$token" --arg model "$model" --arg sf "$small_fast" --arg sn "$sonnet" --arg op "$opus" --arg hk "$haiku")
    [[ -n "$desc" ]] && jq_args+=(--arg description "$desc")
    local hdr=''; [[ -n "$desc" ]] && hdr='description:$description,'
    jq "${jq_args[@]}" ".presets+=[{name:\$name,${hdr}env:{ANTHROPIC_BASE_URL:\$base_url,ANTHROPIC_AUTH_TOKEN:\$token,ANTHROPIC_MODEL:\$model,ANTHROPIC_SMALL_FAST_MODEL:\$sf,ANTHROPIC_DEFAULT_SONNET_MODEL:\$sn,ANTHROPIC_DEFAULT_OPUS_MODEL:\$op,ANTHROPIC_DEFAULT_HAIKU_MODEL:\$hk${extra_json:+,$extra_json}}}]" "$CONFIG_FILE" > "$tmpfile"
  else
    local py_custom=""
    for ((idx=0;idx<${#custom_keys[@]};idx++)); do py_custom="$py_custom"'preset[env]["'${custom_keys[$idx]}'"]="'${custom_vals[$idx]}'"; '; done
    $PYTHON_BIN -c "
import json,sys
d=json.load(open(sys.argv[1]));preset={'name':sys.argv[2]}
if sys.argv[3]:preset['description']=sys.argv[3]
env={'ANTHROPIC_BASE_URL':sys.argv[4],'ANTHROPIC_AUTH_TOKEN':sys.argv[5],'ANTHROPIC_MODEL':sys.argv[6],'ANTHROPIC_SMALL_FAST_MODEL':sys.argv[7],'ANTHROPIC_DEFAULT_SONNET_MODEL':sys.argv[8],'ANTHROPIC_DEFAULT_OPUS_MODEL':sys.argv[9],'ANTHROPIC_DEFAULT_HAIKU_MODEL':sys.argv[10]}
if sys.argv[11].lower()=='y':env['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC']='1'
exec(sys.argv[12]);preset['env']=env;d['presets'].append(preset)
json.dump(d,open(sys.argv[13],'w'),indent=2)
" "$CONFIG_FILE" "$name" "$desc" "$base_url" "$token" "$model" "$small_fast" "$sonnet" "$opus" "$haiku" "$disable_traffic" "$py_custom" "$tmpfile"
  fi
  validate_json "$tmpfile"; mv "$tmpfile" "$CONFIG_FILE"; chmod 600 "$CONFIG_FILE"
  printf "${GREEN}Preset \"%s\" added.${NC}\n" "$name"
}

edit_preset() {
  local count; count=$(get_count)
  [[ "$count" -eq 0 ]] && { printf "${YELLOW}No presets.${NC}\n"; return; }
  printf "\n${BOLD}Edit Preset${NC}\n"
  for ((i=0;i<count;i++)); do printf "  ${BOLD}%d)${NC} %s\n" $((i+1)) "$(get_name "$i")"; done
  printf "  q) Cancel\nChoice: "; read -r pick
  [[ "$pick" == "q" || "$pick" == "Q" ]] && return
  [[ ! "$pick" =~ ^[0-9]+$ || "$pick" -lt 1 || "$pick" -gt "$count" ]] && { printf "${RED}Invalid.${NC}\n"; return; }
  local idx=$((pick-1)) name desc base_url token model sf sn op hk disable
  name=$(get_name "$idx"); desc=$(get_description "$idx"); base_url=$(get_field "$idx" ANTHROPIC_BASE_URL)
  token=$(get_field "$idx" ANTHROPIC_AUTH_TOKEN); model=$(get_field "$idx" ANTHROPIC_MODEL)
  sf=$(get_field "$idx" ANTHROPIC_SMALL_FAST_MODEL); sn=$(get_field "$idx" ANTHROPIC_DEFAULT_SONNET_MODEL)
  op=$(get_field "$idx" ANTHROPIC_DEFAULT_OPUS_MODEL); hk=$(get_field "$idx" ANTHROPIC_DEFAULT_HAIKU_MODEL)
  disable=$(get_field "$idx" CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC)
  while true; do
    local dt="off"; [[ "$disable" == "1" ]] && dt="on"
    local mt="(empty)"; [[ -n "$token" ]] && mt="${token:0:4}...${token: -4}"
    printf "\n${BOLD}Editing: %s${NC}\n" "$name"
    printf "  ${BOLD}1)${NC} Name:%s\n  ${BOLD}2)${NC} Desc:%s\n  ${BOLD}3)${NC} URL:%s\n  ${BOLD}4)${NC} Token:%s\n" "$name" "$desc" "$base_url" "$mt"
    printf "  ${BOLD}5)${NC} Model:%s\n  ${BOLD}6)${NC} SFast:%s\n  ${BOLD}7)${NC} Sonnet:%s\n  ${BOLD}8)${NC} Opus:%s\n  ${BOLD}9)${NC} Haiku:%s\n" "$model" "$sf" "$sn" "$op" "$hk"
    printf "  ${BOLD}0)${NC} NoEssent:%s\n  ${BOLD}s)${NC} Save&done\n  ${BOLD}q)${NC} Cancel\nChoice: " "$dt"
    read -r fc; local v
    case "$fc" in
      1) printf "New name [%s]: " "$name"; read -r v; [[ -n "$v" ]] && name="$v";;
      2) printf "New desc [%s]: " "$desc"; read -r v; desc="$v";;
      3) printf "New URL [%s]: " "$base_url"; read -r v; [[ -n "$v" ]] && base_url="$v";;
      4) printf "New token [%s]: " "$mt"; read -r v; [[ -n "$v" ]] && token="$v";;
      5) printf "New model [%s]: " "$model"; read -r v; [[ -n "$v" ]] && model="$v";;
      6) printf "New sf [%s]: " "$sf"; read -r v; [[ -n "$v" ]] && sf="$v";;
      7) printf "New sn [%s]: " "$sn"; read -r v; [[ -n "$v" ]] && sn="$v";;
      8) printf "New op [%s]: " "$op"; read -r v; [[ -n "$v" ]] && op="$v";;
      9) printf "New hk [%s]: " "$hk"; read -r v; [[ -n "$v" ]] && hk="$v";;
      0) printf "Toggle [y/N]: "; read -r v; [[ "$v" =~ ^[yY] ]] && disable="1" || disable="";;
      s|S)
        local tmpfile; tmpfile=$(mktemp "${CONFIG_FILE}.XXXXXX")
        if [[ "$JSON_PARSE_MODE" == "jq" ]]; then
          local je=".presets[$idx].name=\$name|.presets[$idx].env.ANTHROPIC_BASE_URL=\$bu|.presets[$idx].env.ANTHROPIC_AUTH_TOKEN=\$tk|.presets[$idx].env.ANTHROPIC_MODEL=\$md|.presets[$idx].env.ANTHROPIC_SMALL_FAST_MODEL=\$sf|.presets[$idx].env.ANTHROPIC_DEFAULT_SONNET_MODEL=\$sn|.presets[$idx].env.ANTHROPIC_DEFAULT_OPUS_MODEL=\$op|.presets[$idx].env.ANTHROPIC_DEFAULT_HAIKU_MODEL=\$hk"
          [[ -n "$disable" ]] && je="$je|.presets[$idx].env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=\"1\"" || je="$je|del(.presets[$idx].env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC)"
          local ea=()
          if [[ -n "$desc" ]]; then je="$je|.presets[$idx].description=\$desc"; ea+=(--arg desc "$desc"); else je="$je|del(.presets[$idx].description)"; fi
          jq --arg name "$name" --arg bu "$base_url" --arg tk "$token" --arg md "$model" --arg sf "$sf" --arg sn "$sn" --arg op "$op" --arg hk "$hk" "${ea[@]}" "$je" "$CONFIG_FILE" > "$tmpfile"
        else
          $PYTHON_BIN -c "import json,sys;d=json.load(open(sys.argv[1]));p=d['presets'][int(sys.argv[2])];p['name']=sys.argv[3];(lambda:exec('p[\"description\"]=sys.argv[4]')if sys.argv[4]else p.pop('description',None))();e=p['env'];e.update({'ANTHROPIC_BASE_URL':sys.argv[5],'ANTHROPIC_AUTH_TOKEN':sys.argv[6],'ANTHROPIC_MODEL':sys.argv[7],'ANTHROPIC_SMALL_FAST_MODEL':sys.argv[8],'ANTHROPIC_DEFAULT_SONNET_MODEL':sys.argv[9],'ANTHROPIC_DEFAULT_OPUS_MODEL':sys.argv[10],'ANTHROPIC_DEFAULT_HAIKU_MODEL':sys.argv[11]});(e.__setitem__('CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC','1')if sys.argv[12]=='1'else e.pop('CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC',None));json.dump(d,open(sys.argv[13],'w'),indent=2)" "$CONFIG_FILE" "$idx" "$name" "$desc" "$base_url" "$token" "$model" "$sf" "$sn" "$op" "$hk" "${disable:-0}" "$tmpfile"
        fi
        validate_json "$tmpfile"; mv "$tmpfile" "$CONFIG_FILE"; chmod 600 "$CONFIG_FILE"
        printf "${GREEN}Saved.${NC}\n"; return;; q|Q) return;; *) printf "${RED}Invalid.${NC}\n";;
    esac
  done
}

remove_preset() {
  local count; count=$(get_count)
  [[ "$count" -eq 0 ]] && { printf "${YELLOW}No presets.${NC}\n"; return; }
  printf "\n${BOLD}Remove Preset${NC}\n"
  for ((i=0;i<count;i++)); do printf "  ${BOLD}%d)${NC} %s\n" $((i+1)) "$(get_name "$i")"; done
  printf "  q) Cancel\nChoice: "; read -r pick
  [[ "$pick" == "q" || "$pick" == "Q" ]] && return
  [[ ! "$pick" =~ ^[0-9]+$ || "$pick" -lt 1 || "$pick" -gt "$count" ]] && { printf "${RED}Invalid.${NC}\n"; return; }
  local idx=$((pick-1)) pn; pn=$(get_name "$idx")
  [[ "$count" -eq 1 ]] && printf "${YELLOW}Last preset.${NC}\n"
  printf "Delete \"${RED}%s${NC}\"? [y/N]: " "$pn"; read -r confirm
  [[ ! "$confirm" =~ ^[yY] ]] && { printf "Cancelled.\n"; return; }
  local tmpfile; tmpfile=$(mktemp "${CONFIG_FILE}.XXXXXX")
  if [[ "$JSON_PARSE_MODE" == "jq" ]]; then jq "del(.presets[$idx])" "$CONFIG_FILE" > "$tmpfile"
  else $PYTHON_BIN -c "import json,sys;d=json.load(open(sys.argv[1]));d['presets'].pop($idx);json.dump(d,open(sys.argv[2],'w'),indent=2)" "$CONFIG_FILE" "$tmpfile"; fi
  validate_json "$tmpfile"; mv "$tmpfile" "$CONFIG_FILE"; chmod 600 "$CONFIG_FILE"
  printf "${GREEN}\"%s\" removed.${NC}\n" "$pn"
}

uninstall_mode() {
  printf "${RED}${BOLD}Uninstall Claude Launcher${NC}\n\nThis will delete %s and remove shell alias.\n\n${RED}Continue? [y/N]:${NC} " "$HOME/.config/claude-launcher/"
  read -r confirm; [[ ! "$confirm" =~ ^[yY] ]] && { printf "Cancelled.\n"; exit 0; }
  printf "\nRemoving...\n"
  rm -rf "$HOME/.config/claude-launcher" && printf "  ${GREEN}Deleted${NC} config dir\n" || printf "  ${YELLOW}Failed${NC}\n"
  local m="# claude-launcher" removed=0
  for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
    if [[ -f "$rc" ]] && grep -qF "$m" "$rc" 2>/dev/null; then
      [[ "$(uname -s)" == "Darwin" ]] && sed -i '' "/$m/d" "$rc" || sed -i "/$m/d" "$rc"
      printf "  ${GREEN}Removed${NC} from %s\n" "$rc"; removed=1
    fi
  done
  [[ "$removed" -eq 0 ]] && printf "  ${YELLOW}No alias found.${NC}\n"
  printf "\n${GREEN}Done.${NC} Restart your shell.\n"; exit 0
}

COMMAND="${1:-launch}"
[[ "$COMMAND" == -* ]] && COMMAND="launch" || shift || true
case "$COMMAND" in
  launch) resolve_config; detect_parser; validate_config; check_required_fields; check_permissions; launch_mode "$@";;
  models) resolve_config; detect_parser; validate_config; check_required_fields; models_menu;;
  uninstall) uninstall_mode;;
  *) set -- "$COMMAND" "$@"; resolve_config; detect_parser; validate_config; check_required_fields; check_permissions; launch_mode "$@";;
esac
LAUNCHER
chmod +x "$LAUNCHER"
printf "→ Launcher installed to %s\n" "$LAUNCHER"

# ── Add shell alias ──────────────────────────────────────────
marker="# claude-launcher"
alias_line="alias claude-launcher=\"$LAUNCHER\"  $marker"

case "${SHELL##*/}" in
  zsh)  rc="$HOME/.zshrc" ;;
  bash) rc="$HOME/.bashrc"
        [[ -f "$HOME/.bash_profile" ]] && rc="$HOME/.bash_profile" ;;
  *)    rc=""
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
exit 0

# ---LAUNCHER_START---
# Everything below this line is the launcher script
# that gets written to ~/.config/claude-launcher/claude-launcher.

#!/usr/bin/env bash
set -uo pipefail

VERSION="1.0.0"

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]] && [[ -z "${CLAUDE_LAUNCHER_NO_COLOR:-}" ]]; then
  RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m'
  BLUE='\033[0;34m' BOLD='\033[1m' NC='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' BOLD='' NC=''
fi

die() { printf "${RED}Error:${NC} %s\n" "$1" >&2; exit 1; }
warn() { printf "${YELLOW}Warning:${NC} %s\n" "$1" >&2; }

show_help() {
  cat <<'HELP'
Claude Launcher - Switch Claude Code model presets from a menu.

Usage:
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

DEFAULT_CONFIG="$HOME/.config/claude-launcher/presets.json"

resolve_config() {
  if [[ -n "${CLAUDE_LAUNCHER_CONFIG:-}" ]]; then
    CONFIG_FILE="$CLAUDE_LAUNCHER_CONFIG"
    [[ "$CONFIG_FILE" != /* ]] && CONFIG_FILE="$(pwd)/$CONFIG_FILE"
  else
    CONFIG_FILE="$DEFAULT_CONFIG"
  fi
}

detect_parser() {
  if command -v jq &>/dev/null; then
    JSON_PARSE_MODE="jq"
  elif command -v python3 &>/dev/null; then
    JSON_PARSE_MODE="python"; PYTHON_BIN="python3"
  elif command -v python &>/dev/null; then
    JSON_PARSE_MODE="python"; PYTHON_BIN="python"
  else
    die "Neither jq nor python3 found. Install jq: brew install jq / apt install jq"
  fi
}

validate_json() {
  local file="$1"
  if [[ "$JSON_PARSE_MODE" == "jq" ]]; then
    jq empty "$file" 2>/dev/null || die "Invalid JSON in: $file"
  else
    $PYTHON_BIN -c "import json; json.load(open('$file'))" 2>/dev/null || die "Invalid JSON in: $file"
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

validate_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    die "Config not found: $CONFIG_FILE. Run: claude-launcher install"
  fi
  [[ ! -r "$CONFIG_FILE" ]] && die "Cannot read: $CONFIG_FILE"
  validate_json "$CONFIG_FILE"
}

check_permissions() {
  if find "$CONFIG_FILE" -perm -o+r -maxdepth 0 2>/dev/null | grep -q .; then
    warn "Config file is world-readable (contains API tokens)."
    printf "  ${YELLOW}Fix:${NC} chmod 600 \"%s\"\n" "$CONFIG_FILE" >&2
    printf "  ${YELLOW}Fix now? [y/N]:${NC} " >&2
    read -r ans
    [[ "$ans" == "y" || "$ans" == "Y" ]] && chmod 600 "$CONFIG_FILE" && printf "${GREEN}Permissions updated.${NC}\n" >&2
  fi
}

check_required_fields() {
  local count errors preset_name base_url auth_token
  count=$(get_count); errors=""
  if [[ "$JSON_PARSE_MODE" == "jq" ]]; then
    errors=$(jq -r '.presets | to_entries[] |
      (if (.value.name // "") == "" then "  Preset #\(.key+1): missing \"name\"" else empty end),
      (if (.value.env | type) != "object" or (.value.env // {}) == {} then "  Preset \"\(.value.name // "unnamed")\": missing \"env\"" else empty end)
    ' "$CONFIG_FILE")
    [[ -n "$errors" ]] && { printf "${RED}Validation errors:${NC}\n%s\n" "$errors" >&2; exit 1; }
    for ((i=0; i<count; i++)); do
      preset_name=$(get_name "$i"); base_url=$(get_field "$i" "ANTHROPIC_BASE_URL"); auth_token=$(get_field "$i" "ANTHROPIC_AUTH_TOKEN")
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
    [[ -n "$errors" ]] && { printf "${RED}Validation errors:${NC}\n%s\n" "$errors" >&2; exit 1; }
    for ((i=0; i<count; i++)); do
      preset_name=$(get_name "$i"); base_url=$(get_field "$i" "ANTHROPIC_BASE_URL"); auth_token=$(get_field "$i" "ANTHROPIC_AUTH_TOKEN")
      [[ -z "$base_url" ]] && warn "Preset \"$preset_name\": ANTHROPIC_BASE_URL is empty"
      [[ -z "$auth_token" ]] && warn "Preset \"$preset_name\": ANTHROPIC_AUTH_TOKEN is empty"
    done
  fi
}

launch_mode() {
  local count; count=$(get_count)
  [[ "$count" -eq 0 ]] && die "No presets found. Run: claude-launcher models to add one."
  printf "\n${BOLD}${BLUE}Claude Launcher${NC} ${VERSION}\n\n"
  for ((i=0; i<count; i++)); do printf "  ${BOLD}%2d)${NC} %s\n" $((i+1)) "$(get_name "$i")"; done
  printf "\n  ${BOLD} q)${NC} Quit\n\n"
  while true; do
    printf "Enter choice [1-%d]: " "$count"; read -r choice
    [[ "$choice" == "q" || "$choice" == "Q" ]] && exit 0
    [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )) && break
    printf "${RED}Invalid.${NC} Enter 1-%d or q.\n" "$count"
  done
  printf "\n${GREEN}Starting with \"%s\"...${NC}\n\n" "$(get_name $((choice-1)))"
  while IFS='=' read -r key value; do export "$key"="$value"; done < <(get_env $((choice-1)))
  exec claude "$@"
}

models_menu() {
  printf "\n${BOLD}${BLUE}Model Management${NC}\n\n"
  printf "  ${BOLD}1)${NC} List\n  ${BOLD}2)${NC} Add\n  ${BOLD}3)${NC} Edit\n  ${BOLD}4)${NC} Remove\n  ${BOLD}q)${NC} Back\n\nChoice: "
  read -r action
  case "$action" in
    1) list_presets ;;  2) add_preset ;;  3) edit_preset ;;  4) remove_preset ;;
    q|Q) return 0 ;;  *) printf "${RED}Invalid.${NC}\n"; return 1 ;;
  esac
}

list_presets() {
  local count; count=$(get_count)
  printf "\n${BOLD}Presets:${NC}\n\n"
  [[ "$count" -eq 0 ]] && { printf "  ${YELLOW}(none)${NC}\n"; return; }
  for ((i=0; i<count; i++)); do
    local name desc token base_url model masked
    name=$(get_name "$i"); desc=$(get_description "$i"); base_url=$(get_field "$i" "ANTHROPIC_BASE_URL")
    token=$(get_field "$i" "ANTHROPIC_AUTH_TOKEN"); model=$(get_field "$i" "ANTHROPIC_MODEL")
    masked="(empty)"
    if [[ -n "$token" ]]; then
      [[ ${#token} -gt 8 ]] && masked="${token:0:4}****${token: -4}" || masked="${token:0:1}****"
    fi
    printf "  ${BOLD}%d)${NC} %s\n" $((i+1)) "$name"
    [[ -n "$desc" ]] && printf "     %s\n" "$desc"
    printf "     %-14s %s\n" "Base URL:" "$base_url" "Token:" "$masked" "Model:" "$model"
    echo ""
  done
}

add_preset() {
  local name desc base_url token model small_fast sonnet opus haiku disable_traffic
  printf "\n${BOLD}Add New Preset${NC}\n───────────────\n"
  while true; do printf "Name: "; read -r name; [[ -n "$name" ]] && break; printf "${RED}Name is required.${NC}\n"; done
  printf "Description (optional): "; read -r desc
  printf "API Base URL [https://api.anthropic.com]: "; read -r base_url; base_url="${base_url:-https://api.anthropic.com}"
  printf "Auth Token: "; read -r token
  printf "Default model: "; read -r model
  while [[ -z "$model" ]]; do printf "${RED}Model is required.${NC} Default model: "; read -r model; done
  printf "Small/Fast model [%s]: " "$model"; read -r small_fast; small_fast="${small_fast:-$model}"
  printf "Sonnet model [%s]: " "$model"; read -r sonnet; sonnet="${sonnet:-$model}"
  printf "Opus model [%s]: " "$model"; read -r opus; opus="${opus:-$model}"
  printf "Haiku model [%s]: " "$model"; read -r haiku; haiku="${haiku:-$model}"
  printf "Disable non-essential traffic? [y/N]: "; read -r disable_traffic; disable_traffic="${disable_traffic:-n}"
  printf "Add custom env vars? (KEY=VALUE, empty to finish):\n"
  local custom_keys=() custom_vals=()
  while true; do printf "  > "; read -r line; [[ -z "$line" ]] && break
    [[ "$line" != *"="* ]] && { printf "  ${RED}Must be KEY=VALUE format.${NC}\n"; continue; }
    custom_keys+=("${line%%=*}"); custom_vals+=("${line#*=}")
  done
  local tmpfile extra_json=""; tmpfile=$(mktemp "${CONFIG_FILE}.XXXXXX")
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
      jq "${jq_args[@]}" ".presets += [{name:\$name,description:\$description,env:{ANTHROPIC_BASE_URL:\$base_url,ANTHROPIC_AUTH_TOKEN:\$token,ANTHROPIC_MODEL:\$model,ANTHROPIC_SMALL_FAST_MODEL:\$small_fast,ANTHROPIC_DEFAULT_SONNET_MODEL:\$sonnet,ANTHROPIC_DEFAULT_OPUS_MODEL:\$opus,ANTHROPIC_DEFAULT_HAIKU_MODEL:\$haiku${extra_json:+,$extra_json}}}]" "$CONFIG_FILE" > "$tmpfile"
    else
      jq "${jq_args[@]}" ".presets += [{name:\$name,env:{ANTHROPIC_BASE_URL:\$base_url,ANTHROPIC_AUTH_TOKEN:\$token,ANTHROPIC_MODEL:\$model,ANTHROPIC_SMALL_FAST_MODEL:\$small_fast,ANTHROPIC_DEFAULT_SONNET_MODEL:\$sonnet,ANTHROPIC_DEFAULT_OPUS_MODEL:\$opus,ANTHROPIC_DEFAULT_HAIKU_MODEL:\$haiku${extra_json:+,$extra_json}}}]" "$CONFIG_FILE" > "$tmpfile"
    fi
  else
    local py_custom=""
    for ((idx=0; idx<${#custom_keys[@]}; idx++)); do
      py_custom="$py_custom"'preset[env]["'${custom_keys[$idx]}'"]='"'${custom_vals[$idx]}'"'; '
    done
    $PYTHON_BIN -c "
import json,sys
d=json.load(open(sys.argv[1]))
preset={'name':sys.argv[2]}
dsc=sys.argv[3]
if dsc: preset['description']=dsc
env={'ANTHROPIC_BASE_URL':sys.argv[4],'ANTHROPIC_AUTH_TOKEN':sys.argv[5],'ANTHROPIC_MODEL':sys.argv[6],'ANTHROPIC_SMALL_FAST_MODEL':sys.argv[7],'ANTHROPIC_DEFAULT_SONNET_MODEL':sys.argv[8],'ANTHROPIC_DEFAULT_OPUS_MODEL':sys.argv[9],'ANTHROPIC_DEFAULT_HAIKU_MODEL':sys.argv[10]}
if sys.argv[11].lower()=='y': env['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC']='1'
exec(sys.argv[12])
preset['env']=env
d['presets'].append(preset)
json.dump(d,open(sys.argv[13],'w'),indent=2)
" "$CONFIG_FILE" "$name" "$desc" "$base_url" "$token" "$model" "$small_fast" "$sonnet" "$opus" "$haiku" "$disable_traffic" "$py_custom" "$tmpfile"
  fi
  validate_json "$tmpfile"; mv "$tmpfile" "$CONFIG_FILE"; chmod 600 "$CONFIG_FILE"
  printf "${GREEN}Preset \"%s\" added.${NC}\n" "$name"
}

edit_preset() {
  local count; count=$(get_count)
  [[ "$count" -eq 0 ]] && { printf "${YELLOW}No presets to edit.${NC}\n"; return; }
  printf "\n${BOLD}Edit Preset${NC}\n"
  for ((i=0; i<count; i++)); do printf "  ${BOLD}%d)${NC} %s\n" $((i+1)) "$(get_name "$i")"; done
  printf "  q) Cancel\nChoice: "; read -r pick
  [[ "$pick" == "q" || "$pick" == "Q" ]] && return
  [[ ! "$pick" =~ ^[0-9]+$ || "$pick" -lt 1 || "$pick" -gt "$count" ]] && { printf "${RED}Invalid.${NC}\n"; return; }
  local idx=$((pick-1))
  local name desc base_url token model small_fast sonnet opus haiku disable
  name=$(get_name "$idx"); desc=$(get_description "$idx"); base_url=$(get_field "$idx" "ANTHROPIC_BASE_URL")
  token=$(get_field "$idx" "ANTHROPIC_AUTH_TOKEN"); model=$(get_field "$idx" "ANTHROPIC_MODEL")
  small_fast=$(get_field "$idx" "ANTHROPIC_SMALL_FAST_MODEL"); sonnet=$(get_field "$idx" "ANTHROPIC_DEFAULT_SONNET_MODEL")
  opus=$(get_field "$idx" "ANTHROPIC_DEFAULT_OPUS_MODEL"); haiku=$(get_field "$idx" "ANTHROPIC_DEFAULT_HAIKU_MODEL")
  disable=$(get_field "$idx" "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC")
  while true; do
    local dt_label="off"; [[ "$disable" == "1" ]] && dt_label="on"
    local masked_token="(empty)"; [[ -n "$token" ]] && masked_token="${token:0:4}...${token: -4}"
    printf "\n${BOLD}Editing: %s${NC}\n" "$name"
    printf "  ${BOLD}1)${NC} Name: %s\n" "$name"; printf "  ${BOLD}2)${NC} Description: %s\n" "$desc"
    printf "  ${BOLD}3)${NC} Base URL: %s\n" "$base_url"; printf "  ${BOLD}4)${NC} Token: %s\n" "$masked_token"
    printf "  ${BOLD}5)${NC} Model: %s\n" "$model"; printf "  ${BOLD}6)${NC} Small/Fast: %s\n" "$small_fast"
    printf "  ${BOLD}7)${NC} Sonnet: %s\n" "$sonnet"; printf "  ${BOLD}8)${NC} Opus: %s\n" "$opus"
    printf "  ${BOLD}9)${NC} Haiku: %s\n" "$haiku"; printf "  ${BOLD}0)${NC} No-essent: %s\n" "$dt_label"
    printf "  ${BOLD}s)${NC} Save & done\n  ${BOLD}q)${NC} Cancel\nChoice: "; read -r fc; local v
    case "$fc" in
      1) printf "New name [%s]: " "$name"; read -r v; [[ -n "$v" ]] && name="$v" ;;
      2) printf "New description [%s]: " "$desc"; read -r v; desc="$v" ;;
      3) printf "New base URL [%s]: " "$base_url"; read -r v; [[ -n "$v" ]] && base_url="$v" ;;
      4) printf "New token [%s]: " "$masked_token"; read -r v; [[ -n "$v" ]] && token="$v" ;;
      5) printf "New model [%s]: " "$model"; read -r v; [[ -n "$v" ]] && model="$v" ;;
      6) printf "New small/fast [%s]: " "$small_fast"; read -r v; [[ -n "$v" ]] && small_fast="$v" ;;
      7) printf "New sonnet [%s]: " "$sonnet"; read -r v; [[ -n "$v" ]] && sonnet="$v" ;;
      8) printf "New opus [%s]: " "$opus"; read -r v; [[ -n "$v" ]] && opus="$v" ;;
      9) printf "New haiku [%s]: " "$haiku"; read -r v; [[ -n "$v" ]] && haiku="$v" ;;
      0) printf "Toggle non-essential traffic [y/N]: "; read -r v; [[ "$v" =~ ^[yY] ]] && disable="1" || disable="" ;;
      s|S)
        local tmpfile; tmpfile=$(mktemp "${CONFIG_FILE}.XXXXXX")
        if [[ "$JSON_PARSE_MODE" == "jq" ]]; then
          local jq_expr=".presets[$idx].name=\$name|.presets[$idx].env.ANTHROPIC_BASE_URL=\$base_url|.presets[$idx].env.ANTHROPIC_AUTH_TOKEN=\$token|.presets[$idx].env.ANTHROPIC_MODEL=\$model|.presets[$idx].env.ANTHROPIC_SMALL_FAST_MODEL=\$small_fast|.presets[$idx].env.ANTHROPIC_DEFAULT_SONNET_MODEL=\$sonnet|.presets[$idx].env.ANTHROPIC_DEFAULT_OPUS_MODEL=\$opus|.presets[$idx].env.ANTHROPIC_DEFAULT_HAIKU_MODEL=\$haiku"
          [[ -n "$disable" ]] && jq_expr="$jq_expr|.presets[$idx].env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=\"1\"" || jq_expr="$jq_expr|del(.presets[$idx].env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC)"
          local extra_jq_args=()
          if [[ -n "$desc" ]]; then jq_expr="$jq_expr|.presets[$idx].description=\$description"; extra_jq_args+=(--arg description "$desc")
          else jq_expr="$jq_expr|del(.presets[$idx].description)"; fi
          jq --arg name "$name" --arg base_url "$base_url" --arg token "$token" --arg model "$model" --arg small_fast "$small_fast" --arg sonnet "$sonnet" --arg opus "$opus" --arg haiku "$haiku" "${extra_jq_args[@]}" "$jq_expr" "$CONFIG_FILE" > "$tmpfile"
        else
          $PYTHON_BIN -c "
import json,sys
d=json.load(open(sys.argv[1]));p=d['presets'][int(sys.argv[2])]
p['name']=sys.argv[3]
if sys.argv[4]: p['description']=sys.argv[4]
elif 'description' in p: del p['description']
e=p['env'];e['ANTHROPIC_BASE_URL']=sys.argv[5];e['ANTHROPIC_AUTH_TOKEN']=sys.argv[6]
e['ANTHROPIC_MODEL']=sys.argv[7];e['ANTHROPIC_SMALL_FAST_MODEL']=sys.argv[8]
e['ANTHROPIC_DEFAULT_SONNET_MODEL']=sys.argv[9];e['ANTHROPIC_DEFAULT_OPUS_MODEL']=sys.argv[10]
e['ANTHROPIC_DEFAULT_HAIKU_MODEL']=sys.argv[11]
if sys.argv[12]=='1': e['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC']='1'
elif 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC' in e: del e['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC']
json.dump(d,open(sys.argv[13],'w'),indent=2)
" "$CONFIG_FILE" "$idx" "$name" "$desc" "$base_url" "$token" "$model" "$small_fast" "$sonnet" "$opus" "$haiku" "${disable:-0}" "$tmpfile"
        fi
        validate_json "$tmpfile"; mv "$tmpfile" "$CONFIG_FILE"; chmod 600 "$CONFIG_FILE"
        printf "${GREEN}Saved.${NC}\n"; return ;; q|Q) return ;; *) printf "${RED}Invalid.${NC}\n" ;;
    esac
  done
}

remove_preset() {
  local count; count=$(get_count)
  [[ "$count" -eq 0 ]] && { printf "${YELLOW}No presets to remove.${NC}\n"; return; }
  printf "\n${BOLD}Remove Preset${NC}\n"
  for ((i=0; i<count; i++)); do printf "  ${BOLD}%d)${NC} %s\n" $((i+1)) "$(get_name "$i")"; done
  printf "  q) Cancel\nChoice: "; read -r pick
  [[ "$pick" == "q" || "$pick" == "Q" ]] && return
  [[ ! "$pick" =~ ^[0-9]+$ || "$pick" -lt 1 || "$pick" -gt "$count" ]] && { printf "${RED}Invalid.${NC}\n"; return; }
  local idx=$((pick-1)) preset_name; preset_name=$(get_name "$idx")
  [[ "$count" -eq 1 ]] && printf "${YELLOW}This is the last preset.${NC}\n"
  printf "Delete \"${RED}%s${NC}\"? This cannot be undone. [y/N]: " "$preset_name"; read -r confirm
  [[ ! "$confirm" =~ ^[yY] ]] && { printf "Cancelled.\n"; return; }
  local tmpfile; tmpfile=$(mktemp "${CONFIG_FILE}.XXXXXX")
  if [[ "$JSON_PARSE_MODE" == "jq" ]]; then jq "del(.presets[$idx])" "$CONFIG_FILE" > "$tmpfile"
  else $PYTHON_BIN -c "import json,sys;d=json.load(open(sys.argv[1]));d['presets'].pop($idx);json.dump(d,open(sys.argv[2],'w'),indent=2)" "$CONFIG_FILE" "$tmpfile"; fi
  validate_json "$tmpfile"; mv "$tmpfile" "$CONFIG_FILE"; chmod 600 "$CONFIG_FILE"
  printf "${GREEN}\"%s\" removed.${NC}\n" "$preset_name"
}

# ── Uninstall ────────────────────────────────────────────────
uninstall_mode() {
  printf "${RED}${BOLD}Uninstall Claude Launcher${NC}\n\n"
  printf "This will delete %s and remove shell alias.\n\n" "$HOME/.config/claude-launcher/"
  printf "${RED}Continue? [y/N]:${NC} "; read -r confirm
  [[ ! "$confirm" =~ ^[yY] ]] && { printf "Cancelled.\n"; exit 0; }
  printf "\nRemoving config directory...\n"
  rm -rf "$HOME/.config/claude-launcher" && printf "  ${GREEN}Deleted${NC} %s\n" "$HOME/.config/claude-launcher/" || printf "  ${YELLOW}Failed${NC} — remove manually: rm -rf %s\n" "$HOME/.config/claude-launcher/"
  printf "Removing shell alias...\n"
  local marker="# claude-launcher" removed=0
  for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
    if [[ -f "$rc" ]] && grep -qF "$marker" "$rc" 2>/dev/null; then
      [[ "$(uname -s)" == "Darwin" ]] && sed -i '' "/$marker/d" "$rc" || sed -i "/$marker/d" "$rc"
      printf "  ${GREEN}Removed${NC} from %s\n" "$rc"; removed=1
    fi
  done
  [[ "$removed" -eq 0 ]] && printf "  ${YELLOW}No alias found.${NC}\n"
  printf "\n${GREEN}Claude Launcher uninstalled.${NC} Restart your shell.\n"; exit 0
}

# ── Main dispatch ────────────────────────────────────────────
COMMAND="${1:-launch}"

if [[ "$COMMAND" == -* ]]; then COMMAND="launch"; else shift || true; fi

case "$COMMAND" in
  launch)
    resolve_config; detect_parser; validate_config; check_required_fields; check_permissions
    launch_mode "$@"
    ;;
  models)
    resolve_config; detect_parser; validate_config; check_required_fields
    models_menu
    ;;
  uninstall) uninstall_mode ;;
  *)
    set -- "$COMMAND" "$@"
    resolve_config; detect_parser; validate_config; check_required_fields; check_permissions
    launch_mode "$@"
    ;;
esac
