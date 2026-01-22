#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Enshrouded Dedicated Server - Bulletproof Entrypoint Script
# - Finds SteamCMD whether it's steamcmd, steamcmd.sh, or in weird locations
# - Avoids brittle assumptions about usernames / base image layout
# ============================================================================

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

log()   { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
debug() { echo -e "${CYAN}[DEBUG]${NC} $*"; }

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------
readonly STEAMAPPID="${STEAM_APP_ID:-2278520}"

readonly SERVER_DIR="${SERVER_DIR:-/home/steam/server}"
readonly CONFIG_DIR="${SERVER_CONFIG_DIR:-/home/steam/config}"
readonly CONFIG_FILE="${CONFIG_DIR}/enshrouded_server.json"
readonly SAVEGAME_DIR="${CONFIG_DIR}/savegame"
readonly LOG_DIR="${CONFIG_DIR}/logs"

readonly SERVER_NAME="${SERVER_NAME:-Enshrouded Docker Server}"
readonly SERVER_SLOTS="${SERVER_SLOTS:-16}"
readonly SERVER_PASSWORD="${SERVER_PASSWORD:-}"
readonly GAME_PORT="${GAME_PORT:-15637}"
readonly QUERY_PORT="${QUERY_PORT:-27015}"
readonly UPDATE_ON_START="${UPDATE_ON_START:-1}"

readonly DISPLAY="${DISPLAY:-:99}"

readonly DEFAULT_WINEPREFIX="${WINEPREFIX:-${HOME:-/home/steam}/.wine}"
export WINEPREFIX="${WINEPREFIX:-$DEFAULT_WINEPREFIX}"

print_banner() {
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "   Enshrouded Dedicated Server - Docker Container"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "Steam AppID:      ${STEAMAPPID}"
  info "Server Directory: ${SERVER_DIR}"
  info "Config Directory: ${CONFIG_DIR}"
  info "Wine Prefix:      ${WINEPREFIX}"
  info "Display:          ${DISPLAY}"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ----------------------------------------------------------------------------
# Robust SteamCMD resolution (handles steamcmd OR steamcmd.sh)
# ----------------------------------------------------------------------------
resolve_steamcmd() {
  # 1) Explicit full path override
  if [[ -n "${STEAMCMD:-}" ]] && [[ -x "${STEAMCMD}" ]]; then
    echo "${STEAMCMD}"
    return 0
  fi

  # 2) Directory override
  if [[ -n "${STEAMCMD_DIR:-}" ]] && [[ -x "${STEAMCMD_DIR}/steamcmd.sh" ]]; then
    echo "${STEAMCMD_DIR}/steamcmd.sh"
    return 0
  fi

  # 3) PATH lookups (many images expose steamcmd as a binary)
  if command -v steamcmd >/dev/null 2>&1; then reminding="steamcmd"; echo "steamcmd"; return 0; fi
  if command -v steamcmd.sh >/dev/null 2>&1; then echo "$(command -v steamcmd.sh)"; return 0; fi

  # 4) Common locations
  local p
  for p in \
    "/usr/games/steamcmd" \
    "/usr/bin/steamcmd" \
    "/usr/local/bin/steamcmd" \
    "/opt/steamcmd/steamcmd.sh" \
    "/opt/steamcmd/steamcmd" \
    "/steamcmd/steamcmd.sh" \
    "/steamcmd/steamcmd" \
    "/home/steam/steamcmd/steamcmd.sh" \
    "/home/steam/steamcmd/steamcmd" \
    "/home/ubuntu/steamcmd/steamcmd.sh" \
    "/home/ubuntu/steamcmd/steamcmd"
  do
    if [[ -x "$p" ]]; then
      echo "$p"
      return 0
    fi
  done

  # 5) Last resort: search a bit deeper (still bounded)
  local found
  found="$(find / -maxdepth 8 -type f \( -name steamcmd -o -name steamcmd.sh \) -perm -111 2>/dev/null | head -n 1 || true)"
  if [[ -n "${found}" ]]; then
    echo "${found}"
    return 0
  fi

  return 1
}

resolve_wine() {
  if command -v wine64 >/dev/null 2>&1; then echo "wine64"; return 0; fi
  if command -v wine   >/dev/null 2>&1; then echo "wine";   return 0; fi
  return 1
}

have_xvfb() { command -v Xvfb >/dev/null 2>&1; }

# ----------------------------------------------------------------------------
# Directory + config
# ----------------------------------------------------------------------------
create_directories() {
  log "Creating directories..."
  mkdir -p "${SERVER_DIR}" "${CONFIG_DIR}" "${SAVEGAME_DIR}" "${LOG_DIR}"
  info "✓ Server directory:  ${SERVER_DIR}"
  info "✓ Config directory:  ${CONFIG_DIR}"
  info "✓ Savegame directory:${SAVEGAME_DIR}"
  info "✓ Log directory:     ${LOG_DIR}"
}

generate_config() {
  if [[ -f "${CONFIG_FILE}" ]]; then
    info "Configuration already exists: ${CONFIG_FILE}"
    return 0
  fi

  log "Generating server configuration..."
  local safe_name safe_pass
  safe_name="${SERVER_NAME//$'\n'/ }"
  safe_pass="${SERVER_PASSWORD//$'\n'/ }"

  cat > "${CONFIG_FILE}" <<EOF
{
  "name": "${safe_name}",
  "password": "${safe_pass}",
  "saveDirectory": "./savegame",
  "logDirectory": "./logs",
  "ip": "0.0.0.0",
  "gamePort": ${GAME_PORT},
  "queryPort": ${QUERY_PORT},
  "slotCount": ${SERVER_SLOTS}
}
EOF

  info "✓ Config generated: ${CONFIG_FILE}"
}

prepare_server_config() {
  log "Preparing server configuration..."
  local server_config="${SERVER_DIR}/enshrouded_server.json"
  if [[ -f "${CONFIG_FILE}" ]] && [[ ! -f "${server_config}" ]]; then
    debug "Copying config to server dir"
    cp "${CONFIG_FILE}" "${server_config}"
  fi
  info "✓ Server configuration ready"
}

# ----------------------------------------------------------------------------
# Xvfb
# ----------------------------------------------------------------------------
start_xvfb() {
  if ! have_xvfb; then
    warn "Xvfb not found; continuing without virtual display"
    return 0
  fi

  log "Starting Xvfb..."
  if pgrep -x "Xvfb" >/dev/null 2>&1; then
    info "Xvfb already running"
    return 0
  fi

  Xvfb "${DISPLAY}" -screen 0 1024x768x16 -nolisten tcp -ac &
  sleep 2

  if pgrep -x "Xvfb" >/dev/null 2>&1; then
    info "✓ Xvfb started on ${DISPLAY}"
  else
    error "Failed to start Xvfb"
    return 1
  fi
}

# ----------------------------------------------------------------------------
# SteamCMD update/install
# ----------------------------------------------------------------------------
update_server() {
  if [[ "${UPDATE_ON_START}" != "1" ]]; then
    warn "Auto-update disabled (UPDATE_ON_START != 1)"
    return 0
  fi

  log "Updating/Installing Enshrouded Dedicated Server..."
  info "Steam AppID: ${STEAMAPPID}"
  info "Install dir: ${SERVER_DIR}"

  local steamcmd
  steamcmd="$(resolve_steamcmd)" || {
    error "SteamCMD not found but UPDATE_ON_START=1"
    error "Tried: STEAMCMD, STEAMCMD_DIR, PATH (steamcmd/steamcmd.sh), common locations, and find()."
    error "Fix options:"
    error "  - Use an image that includes steamcmd"
    error "  - Or set STEAMCMD=/full/path/to/steamcmd (inside container)"
    return 1
  }

  debug "SteamCMD resolved: ${steamcmd}"

  # Run SteamCMD (works for both binary and script if executable)
  "${steamcmd}" \
    +@sSteamCmdForcePlatformType windows \
    +force_install_dir "${SERVER_DIR}" \
    +login anonymous \
    +app_update "${STEAMAPPID}" validate \
    +quit

  log "✓ SteamCMD update completed"
}

verify_installation() {
  log "Verifying server installation..."
  local server_exe="${SERVER_DIR}/enshrouded_server.exe"
  if [[ ! -f "${server_exe}" ]]; then
    error "Server executable not found: ${server_exe}"
    return 1
  fi
  info "✓ Found: ${server_exe}"
}

# ----------------------------------------------------------------------------
# Shutdown
# ----------------------------------------------------------------------------
graceful_shutdown() {
  log "Received shutdown signal; stopping..."
  pkill -TERM -f enshrouded_server.exe >/dev/null 2>&1 || true
  sleep 2
  pkill -TERM Xvfb >/dev/null 2>&1 || true
  exit 0
}

# ----------------------------------------------------------------------------
# Preflight
# ----------------------------------------------------------------------------
preflight_checks() {
  log "Running pre-flight checks..."

  if [[ "$(id -u)" -eq 0 ]]; then
    error "Refusing to run as root. Run container as non-root."
    return 1
  fi
  debug "✓ Running as non-root (uid=$(id -u), user=$(id -un))"

  local wine_bin
  wine_bin="$(resolve_wine)" || { error "Wine not found in PATH"; return 1; }
  debug "✓ Wine available: ${wine_bin}"

  if [[ "${UPDATE_ON_START}" == "1" ]]; then
    if ! resolve_steamcmd >/dev/null 2>&1; then
      error "SteamCMD not found but UPDATE_ON_START=1"
      error "If your base image truly includes SteamCMD, it's likely named 'steamcmd' (binary) not 'steamcmd.sh' (script),"
      error "or located deeper than expected. This script already searches for both."
      return 1
    fi
  fi

  if [[ ! -d "${WINEPREFIX}" ]]; then
    warn "Wine prefix directory missing; creating: ${WINEPREFIX}"
    mkdir -p "${WINEPREFIX}" || true
  fi

  if command -v wineboot >/dev/null 2>&1; then
    if [[ ! -f "${WINEPREFIX}/system.reg" ]]; then
      warn "Initializing Wine prefix (wineboot)..."
      wineboot --init || true
      sleep 2
    fi
  fi

  log "✓ Pre-flight checks passed"
}

# ----------------------------------------------------------------------------
# Start server
# ----------------------------------------------------------------------------
start_server() {
  log "Starting Enshrouded Dedicated Server..."
  cd "${SERVER_DIR}"

  local wine_bin
  wine_bin="$(resolve_wine)" || { error "Wine missing at runtime"; exit 1; }

  info "Display:    ${DISPLAY}"
  info "WINEPREFIX: ${WINEPREFIX}"
  info "Wine bin:   ${wine_bin}"

  exec "${wine_bin}" "${SERVER_DIR}/enshrouded_server.exe"
}

main() {
  print_banner
  trap graceful_shutdown SIGTERM SIGINT SIGHUP

  preflight_checks
  create_directories
  generate_config
  start_xvfb
  update_server
  verify_installation
  prepare_server_config
  start_server
}

main "$@"
