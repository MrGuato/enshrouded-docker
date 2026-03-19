#!/usr/bin/env bash
set -uo pipefail   # removed -e intentionally; we handle errors explicitly

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
readonly STEAMCMD_DIR="${STEAMCMD_DIR:-/opt/steamcmd}"

export WINEPREFIX="${WINEPREFIX:-${HOME}/.wine}"
export DISPLAY="${DISPLAY:-:99}"

print_banner() {
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "   Enshrouded Dedicated Server - Docker Container"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "Steam AppID:      ${STEAMAPPID}"
  info "Server Directory: ${SERVER_DIR}"
  info "Config Directory: ${CONFIG_DIR}"
  info "Wine Prefix:      ${WINEPREFIX}"
  info "Display:          ${DISPLAY}"
  info "SteamCMD Dir:     ${STEAMCMD_DIR}"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ----------------------------------------------------------------------------
# Resolve binaries
# ----------------------------------------------------------------------------
resolve_steamcmd() {
  # Prefer the direct path — avoids symlink $0 resolution bugs
  if [[ -x "${STEAMCMD_DIR}/steamcmd.sh" ]]; then
    echo "${STEAMCMD_DIR}/steamcmd.sh"
    return 0
  fi
  if [[ -x "${STEAMCMD_DIR}/steamcmd" ]]; then
    echo "${STEAMCMD_DIR}/steamcmd"
    return 0
  fi
  # Fallback: search PATH (binary, not script — binary doesn't have the $0 bug)
  if command -v steamcmd >/dev/null 2>&1; then
    echo "$(command -v steamcmd)"
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
# Directories + config
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
  cat > "${CONFIG_FILE}" <<EOF
{
  "name": "${SERVER_NAME}",
  "password": "${SERVER_PASSWORD}",
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
  local server_config="${SERVER_DIR}/enshrouded_server.json"
  if [[ -f "${CONFIG_FILE}" ]] && [[ ! -f "${server_config}" ]]; then
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
  rm -f "/tmp/.X${DISPLAY#:}-lock" "/tmp/.X11-unix/X${DISPLAY#:}"
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
# Wine
# ----------------------------------------------------------------------------
init_wine() {
  if ! command -v wineboot >/dev/null 2>&1; then
    warn "wineboot not found; skipping Wine prefix init"
    return 0
  fi
  if [[ ! -f "${WINEPREFIX}/system.reg" ]]; then
    log "Initializing Wine prefix..."
    wineboot --init 2>/dev/null || true
    sleep 5
    info "✓ Wine prefix initialized: ${WINEPREFIX}"
  else
    info "✓ Wine prefix already exists: ${WINEPREFIX}"
  fi
}

# ----------------------------------------------------------------------------
# SteamCMD
# ----------------------------------------------------------------------------
update_server() {
  if [[ "${UPDATE_ON_START}" != "1" ]]; then
    warn "Auto-update disabled"
    return 0
  fi

  local steamcmd
  if ! steamcmd="$(resolve_steamcmd)"; then
    error "SteamCMD not found"
    exit 1
  fi

  log "Initializing SteamCMD..."
  "${steamcmd}" +quit  # let SteamCMD fully bootstrap itself first

  log "Updating/Installing Enshrouded Dedicated Server..."
  debug "SteamCMD: ${steamcmd}"

  "${steamcmd}" \
    +@sSteamCmdForcePlatformType windows \
    +@sSteamCmdForcePlatformBitness 64 \
    +force_install_dir "${SERVER_DIR}" \
    +login anonymous \
    +app_update "${STEAMAPPID}" validate \
    +quit

  info "✓ SteamCMD update completed"
}

verify_installation() {
  log "Verifying server installation..."
  local server_exe="${SERVER_DIR}/enshrouded_server.exe"
  if [[ ! -f "${server_exe}" ]]; then
    error "Server executable not found: ${server_exe}"
    error "SteamCMD may have failed silently. Check the output above."
    exit 1
  fi
  info "✓ Found: ${server_exe}"
}

# ----------------------------------------------------------------------------
# Preflight
# ----------------------------------------------------------------------------
preflight_checks() {
  log "Running pre-flight checks..."

  if [[ "$(id -u)" -eq 0 ]]; then
    error "Refusing to run as root."
    exit 1
  fi
  debug "✓ Running as non-root (uid=$(id -u), user=$(id -un))"

  local wine_bin
  if ! wine_bin="$(resolve_wine)"; then
    error "Wine not found in PATH"
    exit 1
  fi
  debug "✓ Wine available: ${wine_bin}"

  log "✓ Pre-flight checks passed"
}

# ----------------------------------------------------------------------------
# Shutdown + start
# ----------------------------------------------------------------------------
graceful_shutdown() {
  log "Received shutdown signal; stopping..."
  pkill -TERM -f enshrouded_server.exe >/dev/null 2>&1 || true
  sleep 2
  pkill -TERM Xvfb >/dev/null 2>&1 || true
  exit 0
}

start_server() {
  log "Starting Enshrouded Dedicated Server..."
  cd "${SERVER_DIR}"

  local wine_bin
  wine_bin="$(resolve_wine)" || { error "Wine missing at runtime"; exit 1; }

  info "Wine:       ${wine_bin}"
  info "Display:    ${DISPLAY}"
  info "WINEPREFIX: ${WINEPREFIX}"

  exec "${wine_bin}" "${SERVER_DIR}/enshrouded_server.exe"
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
main() {
  print_banner
  trap graceful_shutdown SIGTERM SIGINT SIGHUP

  preflight_checks
  create_directories
  generate_config
  start_xvfb
  init_wine
  update_server
  verify_installation
  prepare_server_config
  start_server
}

main "$@"