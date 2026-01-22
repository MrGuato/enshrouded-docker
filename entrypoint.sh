#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Enshrouded Dedicated Server - Bulletproof Entrypoint Script
# ============================================================================
# Goals:
# - Works even if base image paths/env vars differ (SteamCMD/WINEPREFIX)
# - Avoids brittle assumptions (doesn't require username == "steam")
# - Creates required directories safely
# - Installs/updates via SteamCMD (anonymous) and validates install
# - Starts Xvfb if needed and launches the server via Wine
# ============================================================================

# ----------------------------
# Pretty logging
# ----------------------------
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

# ----------------------------
# Defaults / Configuration
# ----------------------------
# App
readonly STEAMAPPID="${STEAM_APP_ID:-2278520}"

# Paths (match your Dockerfile defaults, but allow override)
readonly SERVER_DIR="${SERVER_DIR:-/home/steam/server}"
readonly CONFIG_DIR="${SERVER_CONFIG_DIR:-/home/steam/config}"
readonly CONFIG_FILE="${CONFIG_DIR}/enshrouded_server.json"
readonly SAVEGAME_DIR="${CONFIG_DIR}/savegame"
readonly LOG_DIR="${CONFIG_DIR}/logs"

# Server settings
readonly SERVER_NAME="${SERVER_NAME:-Enshrouded Docker Server}"
readonly SERVER_SLOTS="${SERVER_SLOTS:-16}"
readonly SERVER_PASSWORD="${SERVER_PASSWORD:-}"
readonly GAME_PORT="${GAME_PORT:-15637}"
readonly QUERY_PORT="${QUERY_PORT:-27015}"
readonly UPDATE_ON_START="${UPDATE_ON_START:-1}"

# Display settings
readonly DISPLAY="${DISPLAY:-:99}"

# Wine prefix (do not assume it exists in base image)
# If already set by the base image, we respect it.
readonly DEFAULT_WINEPREFIX="${WINEPREFIX:-${HOME:-/home/steam}/.wine}"
export WINEPREFIX="${WINEPREFIX:-$DEFAULT_WINEPREFIX}"

# ----------------------------
# Helpers
# ----------------------------
print_banner() {
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "   Enshrouded Dedicated Server - Docker Container"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "Steam AppID:           ${STEAMAPPID}"
  info "Server Directory:      ${SERVER_DIR}"
  info "Config Directory:      ${CONFIG_DIR}"
  info "Wine Prefix:           ${WINEPREFIX}"
  info "Display:               ${DISPLAY}"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Resolve SteamCMD path robustly (no hard dependency on STEAMCMD_DIR)
resolve_steamcmd() {
  # 1) If STEAMCMD is explicitly provided (full path), trust it
  if [[ -n "${STEAMCMD:-}" ]] && [[ -x "${STEAMCMD}" ]]; then
    echo "${STEAMCMD}"
    return 0
  fi

  # 2) If STEAMCMD_DIR provided, use it if valid
  if [[ -n "${STEAMCMD_DIR:-}" ]] && [[ -x "${STEAMCMD_DIR}/steamcmd.sh" ]]; then
    echo "${STEAMCMD_DIR}/steamcmd.sh"
    return 0
  fi

  # 3) Try common locations across images
  local p
  for p in \
    "/home/steam/steamcmd/steamcmd.sh" \
    "/home/steam/Steam/steamcmd.sh" \
    "/home/steam/steamcmd.sh" \
    "/home/ubuntu/steamcmd/steamcmd.sh" \
    "/home/ubuntu/Steam/steamcmd.sh" \
    "/home/ubuntu/steamcmd.sh" \
    "/opt/steamcmd/steamcmd.sh" \
    "/usr/local/bin/steamcmd.sh" \
    "/usr/bin/steamcmd.sh"
  do
    if [[ -x "$p" ]]; then
      echo "$p"
      return 0
    fi
  done

  # 4) Last resort: bounded find
  local found
  found="$(find / -maxdepth 5 -type f -name steamcmd.sh -perm -111 2>/dev/null | head -n 1 || true)"
  if [[ -n "${found}" ]]; then
    echo "${found}"
    return 0
  fi

  return 1
}

# Resolve Wine binary robustly (wine64 preferred, fallback to wine)
resolve_wine() {
  if command -v wine64 >/dev/null 2>&1; then
    echo "wine64"
    return 0
  fi
  if command -v wine >/dev/null 2>&1; then
    echo "wine"
    return 0
  fi
  return 1
}

# Xvfb existence check
have_xvfb() {
  command -v Xvfb >/dev/null 2>&1
}

# ----------------------------
# Directory Management
# ----------------------------
create_directories() {
  log "Creating directories..."
  mkdir -p "${SERVER_DIR}" "${CONFIG_DIR}" "${SAVEGAME_DIR}" "${LOG_DIR}"
  info "✓ Server directory:  ${SERVER_DIR}"
  info "✓ Config directory:  ${CONFIG_DIR}"
  info "✓ Savegame directory:${SAVEGAME_DIR}"
  info "✓ Log directory:     ${LOG_DIR}"
}

# ----------------------------
# Configuration Generation
# ----------------------------
generate_config() {
  if [[ -f "${CONFIG_FILE}" ]]; then
    info "Configuration file already exists: ${CONFIG_FILE}"
    return 0
  fi

  log "Generating server configuration..."

  # Ensure no JSON-breaking newlines (simple hardening)
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

  info "✓ Configuration generated successfully"
  info "  Server Name: ${safe_name}"
  info "  Max Players: ${SERVER_SLOTS}"
  info "  Game Port:   ${GAME_PORT}"
  info "  Query Port:  ${QUERY_PORT}"
  if [[ -n "${SERVER_PASSWORD}" ]]; then
    info "  Password:    Set (hidden)"
  else
    warn "  Password:    Not set (public server)"
  fi
}

prepare_server_config() {
  log "Preparing server configuration..."

  # Keep canonical config in CONFIG_DIR, but ensure server dir has a copy
  local server_config="${SERVER_DIR}/enshrouded_server.json"
  if [[ -f "${CONFIG_FILE}" ]] && [[ ! -f "${server_config}" ]]; then
    debug "Copying config into server directory"
    cp "${CONFIG_FILE}" "${server_config}"
  fi

  info "✓ Server configuration ready"
}

# ----------------------------
# Xvfb Management
# ----------------------------
start_xvfb() {
  if ! have_xvfb; then
    warn "Xvfb not found; continuing without virtual display"
    return 0
  fi

  log "Starting virtual display (Xvfb)..."

  if pgrep -x "Xvfb" >/dev/null 2>&1; then
    info "Xvfb already running"
    return 0
  fi

  Xvfb "${DISPLAY}" -screen 0 1024x768x16 -nolisten tcp -ac &
  local xvfb_pid=$!

  sleep 2

  if pgrep -x "Xvfb" >/dev/null 2>&1; then
    info "✓ Xvfb started successfully on display ${DISPLAY}"
    debug "Xvfb PID: ${xvfb_pid}"
  else
    error "Failed to start Xvfb"
    return 1
  fi
}

# ----------------------------
# SteamCMD Update/Install
# ----------------------------
update_server() {
  if [[ "${UPDATE_ON_START}" != "1" ]]; then
    warn "Auto-update disabled (UPDATE_ON_START != 1)"
    warn "Server will start with existing installation"
    return 0
  fi

  log "Updating/Installing Enshrouded Dedicated Server..."
  info "Steam AppID:       ${STEAMAPPID}"
  info "Install directory: ${SERVER_DIR}"

  local steamcmd
  steamcmd="$(resolve_steamcmd)" || {
    error "SteamCMD not found (steamcmd.sh)."
    error "Set STEAMCMD=/path/to/steamcmd.sh or STEAMCMD_DIR=/path/to/dir"
    return 1
  }
  debug "SteamCMD resolved: ${steamcmd}"

  # Run SteamCMD. Keep it as a single invocation to preserve logs.
  "${steamcmd}" \
    +@sSteamCmdForcePlatformType windows \
    +force_install_dir "${SERVER_DIR}" \
    +login anonymous \
    +app_update "${STEAMAPPID}" validate \
    +quit
}

# ----------------------------
# Installation Verification
# ----------------------------
verify_installation() {
  log "Verifying server installation..."
  local server_exe="${SERVER_DIR}/enshrouded_server.exe"

  if [[ ! -f "${server_exe}" ]]; then
    error "Server executable not found: ${server_exe}"
    error "SteamCMD may have failed or installed to a different directory."
    return 1
  fi

  info "✓ Server executable verified"
  debug "Location: ${server_exe}"

  # Cross-platform stat (mac vs GNU)
  local file_size
  file_size="$(stat -c%s "${server_exe}" 2>/dev/null || stat -f%z "${server_exe}" 2>/dev/null || echo 0)"
  if [[ "${file_size}" -gt 10000000 ]]; then
    debug "File size: $((file_size / 1024 / 1024))MB (looks valid)"
  else
    warn "Server executable seems small: $((file_size / 1024))KB"
  fi
}

# ----------------------------
# Graceful Shutdown
# ----------------------------
graceful_shutdown() {
  log "Received shutdown signal"
  log "Stopping Enshrouded server gracefully..."

  pkill -TERM -f enshrouded_server.exe >/dev/null 2>&1 || true

  local count=0
  while pgrep -f enshrouded_server.exe >/dev/null 2>&1 && [[ ${count} -lt 10 ]]; do
    sleep 1
    ((count++))
  done

  if pgrep -f enshrouded_server.exe >/dev/null 2>&1; then
    warn "Server didn't stop gracefully, forcing shutdown..."
    pkill -KILL -f enshrouded_server.exe >/dev/null 2>&1 || true
  fi

  pkill -TERM Xvfb >/dev/null 2>&1 || true

  log "Server stopped successfully"
  exit 0
}

# ----------------------------
# Pre-flight Checks (bulletproof)
# ----------------------------
preflight_checks() {
  log "Running pre-flight checks..."

  # Do not allow root for safety; do not require username == steam (less brittle)
  if [[ "$(id -u)" -eq 0 ]]; then
    error "Refusing to run as root. Run the container as a non-root user."
    return 1
  fi
  debug "✓ Running as non-root (uid=$(id -u), user=$(id -un))"

  # Resolve wine binary
  local wine_bin
  wine_bin="$(resolve_wine)" || {
    error "Wine not found in PATH"
    return 1
  }
  debug "✓ Wine available: ${wine_bin}"

  # SteamCMD sanity (only required if update is enabled)
  if [[ "${UPDATE_ON_START}" == "1" ]]; then
    local steamcmd
    steamcmd="$(resolve_steamcmd)" || {
      error "SteamCMD not found but UPDATE_ON_START=1"
      error "Set STEAMCMD=/path/to/steamcmd.sh or STEAMCMD_DIR=/path/to/dir"
      return 1
    }
    debug "✓ SteamCMD available: ${steamcmd}"
  fi

  # Initialize wine prefix if missing
  if [[ ! -d "${WINEPREFIX}" ]]; then
    warn "Wine prefix not initialized, creating: ${WINEPREFIX}"
    mkdir -p "${WINEPREFIX}" || true
  fi

  # Try initializing wine prefix (non-fatal if base image handles it differently)
  if command -v wineboot >/dev/null 2>&1; then
    if [[ ! -f "${WINEPREFIX}/system.reg" ]]; then
      warn "Initializing Wine prefix with wineboot..."
      wineboot --init || true
      sleep 3
    fi
  fi
  debug "✓ Wine prefix ready"

  log "✓ All pre-flight checks passed"
}

# ----------------------------
# Server Startup
# ----------------------------
start_server() {
  log "Starting Enshrouded Dedicated Server..."
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "Server Configuration:"
  log "  Name:         ${SERVER_NAME}"
  log "  Max Players:  ${SERVER_SLOTS}"
  log "  Game Port:    ${GAME_PORT}"
  log "  Query Port:   ${QUERY_PORT}"
  log "  Save Dir:     ${SAVEGAME_DIR}"
  log "  Log Dir:      ${LOG_DIR}"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  cd "${SERVER_DIR}"

  local wine_bin
  wine_bin="$(resolve_wine)" || { error "Wine missing at runtime"; exit 1; }

  log "Launching server with Wine..."
  info "Display:     ${DISPLAY}"
  info "WINEPREFIX:  ${WINEPREFIX}"
  info "Wine bin:    ${wine_bin}"

  exec "${wine_bin}" "${SERVER_DIR}/enshrouded_server.exe"
}

# ----------------------------
# Main
# ----------------------------
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
