#!/bin/bash
# Shared setup helpers. Source this file; do not run it directly.

SETUP_DIR="${SETUP_DIR:-$HOME/emacs-mac-setup}"
SETUP_CONFIG="${SETUP_CONFIG:-$SETUP_DIR/setup-emacs-mac.conf}"
SETUP_TEMPLATE="${SETUP_TEMPLATE:-$SETUP_DIR/setup-emacs-mac.conf.template}"
SETUP_STATE="${SETUP_STATE:-$SETUP_DIR/.setup-state}"
SETUP_RUNTIME_KEYCHAIN_PREFIX="${SETUP_RUNTIME_KEYCHAIN_PREFIX:-emacs-mac-setup-runtime}"
SETUP_RUNTIME_SECRET_KEYS="GITHUB_TOKEN GIT_CRYPT_KEY GEMINI_API_KEY ANTHROPIC_API_KEY"

setup_add_homebrew_to_path() {
  [ -f /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
  [ -f /usr/local/bin/brew ]    && eval "$(/usr/local/bin/brew shellenv)"
  export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
}

setup_state_set() {
  local key="$1" value="$2"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  mkdir -p "$SETUP_DIR"
  local tmp
  tmp="$(mktemp)"
  [ -f "$SETUP_STATE" ] || : > "$SETUP_STATE"
  awk -v key="$key" -v value="$value" '
    BEGIN { done = 0 }
    index($0, key "=") == 1 { print key "=\"" value "\""; done = 1; next }
    { print }
    END { if (!done) print key "=\"" value "\"" }
  ' "$SETUP_STATE" > "$tmp"
  mv "$tmp" "$SETUP_STATE"
}

setup_state_get() {
  local key="$1"
  grep "^${key}=" "$SETUP_STATE" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^"//; s/"$//'
}

setup_phase() {
  setup_state_set LAST_PHASE "$1"
  echo ""
  echo "==> $1"
}

setup_fail() {
  local message="$1" next="${2:-bash ~/emacs-mac-setup/setup-doctor.sh}"
  setup_state_set LAST_ERROR "$message"
  setup_state_set NEXT_STEP "$next"
  echo ""
  echo "======================================================================"
  echo "Setup paused"
  echo "======================================================================"
  echo ""
  echo "Problem:"
  echo "  $message"
  echo ""
  echo "Next action:"
  echo "  $next"
  echo ""
  echo "After fixing, resume with:"
  echo "  bash ~/emacs-mac-setup/bootstrap.sh stable --resume"
  echo "======================================================================"
  exit 1
}

setup_gh_auth_status_stored() {
  env -u GITHUB_TOKEN -u GH_TOKEN gh auth status "$@" >/dev/null 2>&1
}

setup_gh_auth_login_with_token() {
  local token="$1"
  [ -n "$token" ] || return 1
  printf '%s\n' "$token" | env -u GITHUB_TOKEN -u GH_TOKEN gh auth login --with-token
  env -u GITHUB_TOKEN -u GH_TOKEN gh auth setup-git
}

setup_ensure_config() {
  mkdir -p "$SETUP_DIR"
  if [ ! -f "$SETUP_CONFIG" ]; then
    [ -f "$SETUP_TEMPLATE" ] || setup_fail "Config template not found: $SETUP_TEMPLATE" "bash ~/emacs-mac-setup/bootstrap.sh stable"
    cp "$SETUP_TEMPLATE" "$SETUP_CONFIG"
    echo "  Created config: $SETUP_CONFIG"
  fi
}

setup_config_get() {
  local key="$1"
  grep "^${key}=" "$SETUP_CONFIG" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^"//; s/"$//'
}

setup_config_set() {
  local key="$1" value="$2"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  setup_ensure_config || return 1
  local tmp
  tmp="$(mktemp)"
  awk -v key="$key" -v value="$value" '
    BEGIN { done = 0 }
    index($0, key "=") == 1 { print key "=\"" value "\""; done = 1; next }
    { print }
    END { if (!done) print key "=\"" value "\"" }
  ' "$SETUP_CONFIG" > "$tmp"
  mv "$tmp" "$SETUP_CONFIG"
}

setup_load_config() {
  setup_ensure_config || return 1
  # shellcheck disable=SC1090
  source "$SETUP_CONFIG"
  BITWARDEN_MASTER_PASSWORD=""
  GITHUB_TOKEN=""
  GIT_CRYPT_KEY=""
  GEMINI_API_KEY=""
  ANTHROPIC_API_KEY=""
  BITWARDEN_EMAIL="${BITWARDEN_EMAIL:-${BW_EMAIL:-}}"
  BW_EMAIL="$BITWARDEN_EMAIL"
}

setup_runtime_var_get() {
  local key="$1"
  eval "printf '%s' \"\${$key:-}\""
}

setup_runtime_load() {
  local prev_master="${BITWARDEN_MASTER_PASSWORD:-}"
  local prev_github="${GITHUB_TOKEN:-}"
  local prev_gitcrypt="${GIT_CRYPT_KEY:-}"
  local prev_gemini="${GEMINI_API_KEY:-}"
  local prev_anthropic="${ANTHROPIC_API_KEY:-}"
  setup_load_config || return 1
  BITWARDEN_MASTER_PASSWORD=""
  GITHUB_TOKEN=""
  GIT_CRYPT_KEY=""
  GEMINI_API_KEY=""
  ANTHROPIC_API_KEY=""
  local keychain_master
  keychain_master="$(setup_keychain_get)"
  if [ -n "$keychain_master" ]; then
    BITWARDEN_MASTER_PASSWORD="$keychain_master"
  elif [ -n "$prev_master" ]; then
    BITWARDEN_MASTER_PASSWORD="$prev_master"
  fi
  setup_runtime_load_secret_keychain_values
  [ -z "${GITHUB_TOKEN:-}" ]      && [ -n "$prev_github" ]    && GITHUB_TOKEN="$prev_github"
  [ -z "${GIT_CRYPT_KEY:-}" ]     && [ -n "$prev_gitcrypt" ]  && GIT_CRYPT_KEY="$prev_gitcrypt"
  [ -z "${GEMINI_API_KEY:-}" ]    && [ -n "$prev_gemini" ]    && GEMINI_API_KEY="$prev_gemini"
  [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -n "$prev_anthropic" ] && ANTHROPIC_API_KEY="$prev_anthropic"
  export GIT_NAME GIT_EMAIL GH_USER GH_REPO
  export BW_ITEM BW_FIELD BW_GH_ITEM BW_ANTHROPIC_ITEM BW_GEMINI_ITEM
  export BW_KEYCHAIN_SERVICE BITWARDEN_EMAIL
  export BITWARDEN_MASTER_PASSWORD GITHUB_TOKEN GIT_CRYPT_KEY
  export ANTHROPIC_API_KEY GEMINI_API_KEY
}

setup_runtime_store_secret() {
  local key="$1" value="$2"
  [ -n "$value" ] || return 0
  printf -v "$key" '%s' "$value"
  export "$key"
  case " $SETUP_RUNTIME_SECRET_KEYS " in
    *" $key "*) setup_runtime_keychain_set "$key" "$value" ;;
  esac
}

setup_runtime_store_bitwarden_master() {
  local password="$1"
  [ -n "$password" ] || return 1
  BITWARDEN_MASTER_PASSWORD="$password"
  export BITWARDEN_MASTER_PASSWORD
  setup_keychain_set "$password" || return 1
}

setup_runtime_require() {
  setup_runtime_load || return 1
  local missing="" key
  for key in "$@"; do
    if [ -z "$(setup_runtime_var_get "$key")" ]; then
      missing="${missing}${key} "
    fi
  done
  if [ -n "$missing" ]; then
    setup_fail "Missing required runtime value(s): $missing" "bash ~/emacs-mac-setup/setup-intake.sh --repair config"
    return 1
  fi
}

setup_prompt() {
  local prompt="$1" default="${2:-}" value
  if [ -n "$default" ]; then
    printf "  %-58s [%s]: " "$prompt" "$default" > /dev/tty
  else
    printf "  %-58s: " "$prompt" > /dev/tty
  fi
  read -r value < /dev/tty
  printf '%s' "${value:-$default}"
}

setup_prompt_secret() {
  local prompt="$1" value
  printf "  %-58s: " "$prompt" > /dev/tty
  read -rs value < /dev/tty
  echo "" > /dev/tty
  printf '%s' "$value"
}

setup_prompt_config_if_empty() {
  local key="$1" prompt="$2" default="$3" value
  value="$(setup_config_get "$key")"
  if [ -z "$value" ]; then
    value="$(setup_prompt "$prompt" "$default")"
    [ -n "$value" ] && setup_config_set "$key" "$value"
  fi
}

setup_require_config() {
  local missing="" key
  for key in "$@"; do
    if [ -z "$(setup_config_get "$key")" ]; then
      missing="${missing}${key} "
    fi
  done
  if [ -n "$missing" ]; then
    setup_fail "Missing required config value(s): $missing" "bash ~/emacs-mac-setup/setup-intake.sh --repair config"
    return 1
  fi
}

setup_require_bitwarden_email() {
  setup_load_config || return 1
  if [ -z "${BITWARDEN_EMAIL:-}" ]; then
    setup_fail "Missing required config value(s): BITWARDEN_EMAIL " "bash ~/emacs-mac-setup/setup-intake.sh --repair config"
    return 1
  fi
}

setup_try_load_private_config_from_github() {
  setup_runtime_load || return 1
  [ -n "${GH_USER:-}" ] || return 0
  command -v gh >/dev/null 2>&1 || return 0
  gh auth status >/dev/null 2>&1 || return 0

  local candidates="" repo seen="" conf_content conf_tmp
  [ -n "${GH_REPO:-}" ] && candidates="$candidates $GH_REPO"
  candidates="$candidates emacs emacs-data"

  for repo in $candidates; do
    case " $seen " in
      *" $repo "*) continue ;;
    esac
    seen="$seen $repo"
    conf_content="$(gh api "repos/$GH_USER/$repo/contents/config/setup-emacs-mac.conf" --jq '.content' 2>/dev/null)" || true
    [ -n "$conf_content" ] || continue
    conf_tmp="$(mktemp)"
    echo "$conf_content" | tr -d '\n' | python3 -c "import sys,base64; sys.stdout.buffer.write(base64.b64decode(sys.stdin.read()))" > "$conf_tmp" 2>/dev/null || true
    if grep -q '^GIT_NAME="[^"]' "$conf_tmp" 2>/dev/null; then
      cp "$conf_tmp" "$SETUP_CONFIG"
      rm -f "$conf_tmp"
      echo "  Loaded existing config from $GH_USER/$repo."
      setup_runtime_load
      return 0
    fi
    rm -f "$conf_tmp"
  done
}

setup_keychain_get() {
  local account="${BITWARDEN_EMAIL:-}" service="${BW_KEYCHAIN_SERVICE:-bitwarden-master}"
  [ -n "$account" ] || return 0
  security find-generic-password -a "$account" -s "$service" -w 2>/dev/null || true
}

setup_keychain_account() {
  printf '%s' "${BITWARDEN_EMAIL:-}"
}

setup_keychain_service() {
  printf '%s' "${BW_KEYCHAIN_SERVICE:-bitwarden-master}"
}

setup_keychain_require_identity() {
  [ -n "${BITWARDEN_EMAIL:-}" ] || setup_fail "Bitwarden email is required before using macOS Keychain." "bash ~/emacs-mac-setup/setup-intake.sh --repair bitwarden"
  [ -n "${BW_KEYCHAIN_SERVICE:-}" ] || setup_fail "Bitwarden Keychain service label is missing." "bash ~/emacs-mac-setup/setup-intake.sh --repair config"
  return 0
}

setup_keychain_set() {
  local password="$1" account service
  [ -n "$password" ] || return 1
  setup_keychain_require_identity || return 1
  account="$(setup_keychain_account)"
  service="$(setup_keychain_service)"
  [ -n "$account" ] || return 1
  security delete-generic-password -a "$account" -s "$service" 2>/dev/null || true
  security add-generic-password -a "$account" -s "$service" -w "$password" -A 2>/dev/null || return 1
}

setup_runtime_keychain_service() {
  printf '%s:%s' "$SETUP_RUNTIME_KEYCHAIN_PREFIX" "$1"
}

setup_runtime_keychain_get() {
  local key="$1" account="$USER" service
  service="$(setup_runtime_keychain_service "$key")"
  security find-generic-password -a "$account" -s "$service" -w 2>/dev/null || true
}

setup_runtime_keychain_set() {
  local key="$1" value="$2" account="$USER" service
  [ -n "$value" ] || return 0
  service="$(setup_runtime_keychain_service "$key")"
  security delete-generic-password -a "$account" -s "$service" 2>/dev/null || true
  security add-generic-password -a "$account" -s "$service" -w "$value" -A >/dev/null
}

setup_runtime_load_secret_keychain_values() {
  local key value
  for key in $SETUP_RUNTIME_SECRET_KEYS; do
    if [ -z "$(setup_runtime_var_get "$key")" ]; then
      value="$(setup_runtime_keychain_get "$key")"
      [ -n "$value" ] && printf -v "$key" '%s' "$value"
    fi
  done
  return 0
}

setup_runtime_cleanup_secret_keychain() {
  local key account="$USER" service
  for key in $SETUP_RUNTIME_SECRET_KEYS; do
    service="$(setup_runtime_keychain_service "$key")"
    security delete-generic-password -a "$account" -s "$service" 2>/dev/null || true
  done
}

setup_install_bitwarden_tools() {
  setup_add_homebrew_to_path
  command -v brew >/dev/null 2>&1 || setup_fail "Homebrew is required before Bitwarden setup." "bash ~/emacs-mac-setup/bootstrap.sh stable"
  if ! command -v bw >/dev/null 2>&1; then
    echo "  Installing Bitwarden CLI..."
    brew install bitwarden-cli
  fi
  if [ ! -d "/Applications/Bitwarden.app" ] && [ ! -d "$HOME/Applications/Bitwarden.app" ]; then
    echo "  Installing Bitwarden desktop app..."
    brew install --cask bitwarden || echo "  WARN: Bitwarden app install failed; CLI setup can still continue."
  fi
}

setup_bw_status() {
  command -v bw >/dev/null 2>&1 || { echo "missing"; return; }
  bw status 2>/dev/null | sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

setup_bw_unlock_with_keychain() {
  setup_runtime_load || return 1
  command -v bw >/dev/null 2>&1 || setup_fail "Bitwarden CLI is not installed." "bash ~/emacs-mac-setup/setup-intake.sh --repair bitwarden"
  local master status session
  master="${BITWARDEN_MASTER_PASSWORD:-}"
  [ -n "$master" ] || setup_fail "Bitwarden master password is missing from config and macOS Keychain." "bash ~/emacs-mac-setup/setup-intake.sh --repair bitwarden"
  export __BW_PW="$master"
  status="$(setup_bw_status)"
  if [ "$status" = "unauthenticated" ]; then
    [ -n "${BITWARDEN_EMAIL:-}" ] || setup_fail "Bitwarden email is missing from setup config." "bash ~/emacs-mac-setup/setup-intake.sh --repair bitwarden"
    session="$(bw login "$BITWARDEN_EMAIL" --passwordenv __BW_PW --raw 2>/dev/null)" || true
  else
    session="$(bw unlock --passwordenv __BW_PW --raw 2>/dev/null)" || true
  fi
  unset __BW_PW
  [ -n "$session" ] || setup_fail "Bitwarden login/unlock failed. Password, email, or 2FA state needs attention." "bash ~/emacs-mac-setup/setup-intake.sh --repair bitwarden"
  export BW_SESSION="$session"
  bw sync --session "$BW_SESSION" >/dev/null 2>&1 || true
}

setup_runtime_import_secret_from_bitwarden() {
  local config_key="$1" item="$2" field="$3" value
  [ -n "$(setup_runtime_var_get "$config_key")" ] && return 0
  [ -n "$item" ] || return 0
  [ -n "$field" ] || return 0
  value="$(setup_bw_get_field "$item" "$field")" || true
  [ -n "$value" ] || return 0
  setup_runtime_store_secret "$config_key" "$value"
}

setup_runtime_load_bitwarden_secrets() {
  setup_bw_unlock_with_keychain || return 1
  setup_runtime_import_secret_from_bitwarden GITHUB_TOKEN "$BW_GH_ITEM" "$BW_FIELD"
  setup_runtime_import_secret_from_bitwarden GIT_CRYPT_KEY "$BW_ITEM" "$BW_FIELD"
  setup_runtime_import_secret_from_bitwarden GEMINI_API_KEY "$BW_GEMINI_ITEM" "$BW_FIELD"
  setup_runtime_import_secret_from_bitwarden ANTHROPIC_API_KEY "$BW_ANTHROPIC_ITEM" "$BW_FIELD"
}

setup_runtime_mirror_secret_to_bitwarden() {
  local config_key="$1" item="$2" field="$3" value
  value="$(setup_runtime_var_get "$config_key")"
  [ -n "$value" ] || return 0
  setup_bw_create_item "$item" "$field" "$value"
}

setup_bw_get_field() {
  local item="$1" field="$2"
  [ -n "$item" ] || return 0
  [ -n "$field" ] || return 0
  bw get item "$item" --session "$BW_SESSION" 2>/dev/null \
    | python3 -c "
import sys,json
d=json.load(sys.stdin)
f=[x.get('value','') for x in d.get('fields',[]) if x.get('name')=='$field']
print((f[0] if f else (d.get('login') or {}).get('password') or '').strip())
" 2>/dev/null || true
}

setup_bw_create_item() {
  local name="$1" field="$2" value="$3"
  [ -n "$name" ]  || setup_fail "Refusing to create a Bitwarden item with an empty name." "bash ~/emacs-mac-setup/setup-intake.sh --repair config"
  [ -n "$field" ] || setup_fail "Refusing to create Bitwarden item '$name' with an empty field name." "bash ~/emacs-mac-setup/setup-intake.sh --repair config"
  [ -n "$value" ] || return 0
  local encoded item_id
  if bw get item "$name" --session "$BW_SESSION" >/dev/null 2>&1; then
    item_id="$(bw get item "$name" --session "$BW_SESSION" 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))")"
    encoded=$(bw get item "$name" --session "$BW_SESSION" 2>/dev/null | python3 -c "
import json,sys
field,value=sys.argv[1],sys.argv[2]
d=json.load(sys.stdin)
d.setdefault('login', {})['password']=value
fields=d.setdefault('fields', [])
for item in fields:
    if item.get('name') == field:
        item['value'] = value
        item['type'] = 1
        break
else:
    fields.append({'name': field, 'value': value, 'type': 1})
print(json.dumps(d))
" "$field" "$value" | bw encode)
    [ -n "$item_id" ] || setup_fail "Could not resolve Bitwarden item id for '$name'." "bash ~/emacs-mac-setup/setup-intake.sh --repair bitwarden"
    echo "$encoded" | bw edit item "$item_id" --session "$BW_SESSION" >/dev/null
    echo "  Updated: $name"
    return 0
  fi
  encoded=$(python3 -c "
import json,sys
name,field,value=sys.argv[1],sys.argv[2],sys.argv[3]
print(json.dumps({'type':1,'name':name,'login':{'password':value},'fields':[{'name':field,'value':value,'type':1}]}))
" "$name" "$field" "$value" | bw encode)
  echo "$encoded" | bw create item --session "$BW_SESSION" >/dev/null
  echo "  Created: $name"
}

setup_print_inventory() {
  setup_runtime_load || return 1
  echo ""
  echo "Detected setup inventory:"
  echo ""
  echo "Config:"
  echo "  setup-emacs-mac.conf      $([ -f "$SETUP_CONFIG" ] && echo found || echo missing)"
  echo "  GH_USER                   ${GH_USER:-<local mode>}"
  echo "  GH_REPO                   ${GH_REPO:-emacs-data}"
  echo "  BW_FIELD                  ${BW_FIELD:-<missing>}"
  echo "  BW_GEMINI_ITEM            ${BW_GEMINI_ITEM:-<missing>}"
  echo "  BITWARDEN_EMAIL           ${BITWARDEN_EMAIL:-<missing>}"
  echo ""
  echo "macOS Keychain:"
  if [ -n "${BW_KEYCHAIN_SERVICE:-}" ] && [ -n "$(setup_keychain_get)" ]; then
    echo "  Bitwarden password        found"
  else
    echo "  Bitwarden password        missing"
  fi
  echo ""
  echo "Tools:"
  echo "  Homebrew                  $(command -v brew >/dev/null 2>&1 && echo installed || echo missing)"
  echo "  GitHub CLI                $(command -v gh >/dev/null 2>&1 && echo installed || echo missing)"
  echo "  Bitwarden CLI             $(command -v bw >/dev/null 2>&1 && echo installed || echo missing)"
  echo "  Bitwarden status          $(setup_bw_status 2>/dev/null || echo unknown)"
  echo ""
}
