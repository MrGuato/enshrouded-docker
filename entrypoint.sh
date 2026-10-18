#!/usr/bin/env bash
set -uo pipefail

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

readonly STEAMAPPID="${STEAM_APP_ID:-2278520}"
readonly SERVER_DIR="${SERVER_DIR:-/home/steam/server}"
readonly CONFIG_DIR="${SERVER_CONFIG_DIR:-/home/steam/config}"
readonly CONFIG_FILE="${CONFIG_DIR}/enshrouded_server.json"
readonly SAVEGAME_DIR="${CONFIG_DIR}/savegame"
readonly LOG_DIR="${CONFIG_DIR}/logs"

readonly SERVER_NAME="${SERVER_NAME:-Enshrouded Docker Server}"
readonly SERVER_SLOTS="${SERVER_SLOTS:-16}"
readonly SERVER_PASSWORD="${SERVER_PASSWORD:-}"
readonly ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
readonly FRIEND_PASSWORD="${FRIEND_PASSWORD:-}"
readonly GUEST_PASSWORD="${GUEST_PASSWORD:-}"
readonly SERVER_IP="${SERVER_IP:-0.0.0.0}"
readonly GAME_PORT="${GAME_PORT:-15637}"
readonly QUERY_PORT="${QUERY_PORT:-15637}"
readonly ENABLE_VOICE_CHAT="${ENABLE_VOICE_CHAT:-false}"
readonly ENABLE_TEXT_CHAT="${ENABLE_TEXT_CHAT:-false}"
readonly VOICE_CHAT_MODE="${VOICE_CHAT_MODE:-Proximity}"
readonly GAME_SETTINGS_PRESET="${GAME_SETTINGS_PRESET:-Default}"

readonly UPDATE_ON_START="${UPDATE_ON_START:-1}"
readonly SYNC_CONFIG_ON_START="${SYNC_CONFIG_ON_START:-1}"
readonly STEAMCMD_RETRIES="${STEAMCMD_RETRIES:-3}"
readonly STEAMCMD_DIR="${STEAMCMD_DIR:-/opt/steamcmd}"

export WINEPREFIX="${WINEPREFIX:-${HOME}/.wine}"
export DISPLAY="${DISPLAY:-:99}"
export WINEARCH="${WINEARCH:-win64}"
export WINEDEBUG="${WINEDEBUG:--all}"

SERVER_PID=""
SHUTTING_DOWN=0

print_banner() {
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "   Enshrouded Dedicated Server — Docker Container"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "Steam AppID:      ${STEAMAPPID}"
  info "Server Name:      ${SERVER_NAME}"
  info "Max Players:      ${SERVER_SLOTS}"
  info "Query/Game Port:  ${QUERY_PORT}/udp"
  info "Server Directory: ${SERVER_DIR}"
  info "Config Directory: ${CONFIG_DIR}"
  info "Wine Prefix:      ${WINEPREFIX}"
  info "Auto-Update:      ${UPDATE_ON_START}"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

resolve_steamcmd() {
  if [[ -x "${STEAMCMD_DIR}/steamcmd.sh" ]]; then echo "${STEAMCMD_DIR}/steamcmd.sh"; return 0; fi
  if [[ -x "${STEAMCMD_DIR}/steamcmd" ]];    then echo "${STEAMCMD_DIR}/steamcmd";    return 0; fi
  if command -v steamcmd >/dev/null 2>&1;    then command -v steamcmd;                return 0; fi
  return 1
}

resolve_wine() {
  if command -v wine64 >/dev/null 2>&1; then echo "wine64"; return 0; fi
  if command -v wine   >/dev/null 2>&1; then echo "wine";   return 0; fi
  return 1
}

have_xvfb() { command -v Xvfb >/dev/null 2>&1; }

preflight_checks() {
  log "Running pre-flight checks..."
  debug "✓ Running as uid=$(id -u) ($(id -un)), gid=$(id -g) ($(id -gn))"

  local wine_bin
  if ! wine_bin="$(resolve_wine)"; then
    error "Wine not found in PATH"
    exit 1
  fi
  debug "✓ Wine available: ${wine_bin}"
  log "✓ Pre-flight checks passed"
}

create_directories() {
  log "Ensuring directories and persistence links..."
  mkdir -p "${SERVER_DIR}" "${CONFIG_DIR}" "${SAVEGAME_DIR}" "${LOG_DIR}" "${WINEPREFIX}"

  # Migrate and symlink savegame directory so './savegame' inside SERVER_DIR writes to CONFIG_DIR/savegame
  if [[ -d "${SERVER_DIR}/savegame" && ! -L "${SERVER_DIR}/savegame" ]]; then
    info "Migrating existing savegames from ${SERVER_DIR}/savegame to ${SAVEGAME_DIR}..."
    cp -rn "${SERVER_DIR}/savegame/." "${SAVEGAME_DIR}/" 2>/dev/null || true
    rm -rf "${SERVER_DIR}/savegame"
  fi
  ln -sfn "${SAVEGAME_DIR}" "${SERVER_DIR}/savegame"

  # Migrate and symlink logs directory so './logs' inside SERVER_DIR writes to CONFIG_DIR/logs
  if [[ -d "${SERVER_DIR}/logs" && ! -L "${SERVER_DIR}/logs" ]]; then
    info "Migrating existing logs from ${SERVER_DIR}/logs to ${LOG_DIR}..."
    cp -rn "${SERVER_DIR}/logs/." "${LOG_DIR}/" 2>/dev/null || true
    rm -rf "${SERVER_DIR}/logs"
  fi
  ln -sfn "${LOG_DIR}" "${SERVER_DIR}/logs"

  info "✓ Savegame directory linked: ${SAVEGAME_DIR}"
  info "✓ Log directory linked:      ${LOG_DIR}"
}

build_user_groups_json() {
  if [[ -n "${ADMIN_PASSWORD}" || -n "${FRIEND_PASSWORD}" || -n "${GUEST_PASSWORD}" ]]; then
    jq -n \
      --arg admin_pw "${ADMIN_PASSWORD}" \
      --arg friend_pw "${FRIEND_PASSWORD}" \
      --arg guest_pw "${GUEST_PASSWORD}" \
      '[
        (if $admin_pw != "" then {
          name: "Admin",
          password: $admin_pw,
          canKickBan: true,
          canAccessInventories: true,
          canEditBase: true,
          canExtendBase: true,
          reservedSlots: 0
        } else empty end),
        (if $friend_pw != "" then {
          name: "Friend",
          password: $friend_pw,
          canKickBan: false,
          canAccessInventories: true,
          canEditBase: true,
          canExtendBase: true,
          reservedSlots: 0
        } else empty end),
        (if $guest_pw != "" then {
          name: "Guest",
          password: $guest_pw,
          canKickBan: false,
          canAccessInventories: false,
          canEditBase: false,
          canExtendBase: false,
          reservedSlots: 0
        } else empty end)
      ]'
  elif [[ -n "${SERVER_PASSWORD}" ]]; then
    jq -n \
      --arg pw "${SERVER_PASSWORD}" \
      '[{
        name: "Default",
        password: $pw,
        canKickBan: true,
        canAccessInventories: true,
        canEditBase: true,
        canExtendBase: true,
        reservedSlots: 0
      }]'
  else
    echo "[]"
  fi
}

configure_server() {
  local server_config="${SERVER_DIR}/enshrouded_server.json"

  # If a real config file exists in SERVER_DIR but not in CONFIG_DIR, migrate it first
  if [[ -f "${server_config}" && ! -L "${server_config}" && ! -f "${CONFIG_FILE}" ]]; then
    mv "${server_config}" "${CONFIG_FILE}"
  fi

  local voice_bool="false"
  [[ "${ENABLE_VOICE_CHAT,,}" == "true" || "${ENABLE_VOICE_CHAT}" == "1" ]] && voice_bool="true"

  local text_bool="false"
  [[ "${ENABLE_TEXT_CHAT,,}" == "true" || "${ENABLE_TEXT_CHAT}" == "1" ]] && text_bool="true"

  if [[ ! -f "${CONFIG_FILE}" ]] || ! jq empty "${CONFIG_FILE}" >/dev/null 2>&1; then
    log "Generating initial server configuration: ${CONFIG_FILE}"
    local user_groups="[]"
    if command -v jq >/dev/null 2>&1; then
      user_groups="$(build_user_groups_json)"
      jq -n \
        --arg name "${SERVER_NAME}" \
        --arg pw "${SERVER_PASSWORD}" \
        --arg ip "${SERVER_IP}" \
        --argjson gamePort "${GAME_PORT}" \
        --argjson queryPort "${QUERY_PORT}" \
        --argjson slotCount "${SERVER_SLOTS}" \
        --arg voiceMode "${VOICE_CHAT_MODE}" \
        --argjson enableVoice "${voice_bool}" \
        --argjson enableText "${text_bool}" \
        --arg preset "${GAME_SETTINGS_PRESET}" \
        --argjson userGroups "${user_groups}" \
        '{
          name: $name,
          password: $pw,
          saveDirectory: "./savegame",
          logDirectory: "./logs",
          ip: $ip,
          gamePort: $gamePort,
          queryPort: $queryPort,
          slotCount: $slotCount,
          voiceChatMode: $voiceMode,
          enableVoiceChat: $enableVoice,
          enableTextChat: $enableText,
          gameSettingsPreset: $preset,
          userGroups: $userGroups
        }' > "${CONFIG_FILE}"
    else
      cat > "${CONFIG_FILE}" <<EOF
{
  "name": "${SERVER_NAME}",
  "password": "${SERVER_PASSWORD}",
  "saveDirectory": "./savegame",
  "logDirectory": "./logs",
  "ip": "${SERVER_IP}",
  "gamePort": ${GAME_PORT},
  "queryPort": ${QUERY_PORT},
  "slotCount": ${SERVER_SLOTS}
}
EOF
    fi
    info "✓ Initial config generated: ${CONFIG_FILE}"
  elif [[ "${SYNC_CONFIG_ON_START}" == "1" ]] && command -v jq >/dev/null 2>&1; then
    log "Syncing environment variables into ${CONFIG_FILE}..."
    local tmp_cfg="${CONFIG_FILE}.tmp"
    local user_groups
    user_groups="$(build_user_groups_json)"

    if [[ -n "${ADMIN_PASSWORD}" || -n "${FRIEND_PASSWORD}" || -n "${GUEST_PASSWORD}" || -n "${SERVER_PASSWORD}" ]]; then
      jq \
        --arg name "${SERVER_NAME}" \
        --arg pw "${SERVER_PASSWORD}" \
        --arg ip "${SERVER_IP}" \
        --argjson gamePort "${GAME_PORT}" \
        --argjson queryPort "${QUERY_PORT}" \
        --argjson slotCount "${SERVER_SLOTS}" \
        --arg voiceMode "${VOICE_CHAT_MODE}" \
        --argjson enableVoice "${voice_bool}" \
        --argjson enableText "${text_bool}" \
        --arg preset "${GAME_SETTINGS_PRESET}" \
        --argjson userGroups "${user_groups}" \
        '.name = $name
         | .password = $pw
         | .saveDirectory = "./savegame"
         | .logDirectory = "./logs"
         | .ip = $ip
         | .gamePort = $gamePort
         | .queryPort = $queryPort
         | .slotCount = $slotCount
         | .voiceChatMode = $voiceMode
         | .enableVoiceChat = $enableVoice
         | .enableTextChat = $enableText
         | .gameSettingsPreset = (.gameSettingsPreset // $preset)
         | .userGroups = $userGroups' "${CONFIG_FILE}" > "${tmp_cfg}" && mv "${tmp_cfg}" "${CONFIG_FILE}"
    else
      jq \
        --arg name "${SERVER_NAME}" \
        --arg ip "${SERVER_IP}" \
        --argjson gamePort "${GAME_PORT}" \
        --argjson queryPort "${QUERY_PORT}" \
        --argjson slotCount "${SERVER_SLOTS}" \
        --arg voiceMode "${VOICE_CHAT_MODE}" \
        --argjson enableVoice "${voice_bool}" \
        --argjson enableText "${text_bool}" \
        '.name = $name
         | .saveDirectory = "./savegame"
         | .logDirectory = "./logs"
         | .ip = $ip
         | .gamePort = $gamePort
         | .queryPort = $queryPort
         | .slotCount = $slotCount
         | .voiceChatMode = $voiceMode
         | .enableVoiceChat = $enableVoice
         | .enableTextChat = $enableText' "${CONFIG_FILE}" > "${tmp_cfg}" && mv "${tmp_cfg}" "${CONFIG_FILE}"
    fi
    info "✓ Configuration synced with environment variables"
  else
    info "Using existing configuration without sync (SYNC_CONFIG_ON_START=${SYNC_CONFIG_ON_START})"
  fi

  # Symlink SERVER_DIR/enshrouded_server.json -> CONFIG_FILE so edits/migrations stay in sync
  rm -f "${server_config}"
  ln -s "${CONFIG_FILE}" "${server_config}"
  info "✓ Server configuration linked: ${server_config} -> ${CONFIG_FILE}"
}

start_xvfb() {
  if ! have_xvfb; then
    warn "Xvfb not found; continuing without virtual display"
    return 0
  fi
  log "Starting Xvfb virtual display on ${DISPLAY}..."
  if pgrep -x "Xvfb" >/dev/null 2>&1; then
    info "✓ Xvfb already running"
    return 0
  fi
  rm -f "/tmp/.X${DISPLAY#:}-lock" "/tmp/.X11-unix/X${DISPLAY#:}" 2>/dev/null || true
  Xvfb "${DISPLAY}" -screen 0 1024x768x16 -nolisten tcp -ac >/dev/null 2>&1 &
  sleep 2
  if pgrep -x "Xvfb" >/dev/null 2>&1; then
    info "✓ Xvfb started on ${DISPLAY}"
  else
    error "Failed to start Xvfb"
    return 1
  fi
}

init_wine() {
  if ! command -v wineboot >/dev/null 2>&1; then
    warn "wineboot not found; skipping Wine prefix init"
    return 0
  fi
  if [[ ! -f "${WINEPREFIX}/system.reg" ]]; then
    log "Initializing Wine prefix (${WINEPREFIX})..."
    export DISPLAY WINEARCH WINEPREFIX WINEDEBUG
    wineboot --init >/dev/null 2>&1 || wineboot --init
    wineserver --wait || true
    if [[ -f "${WINEPREFIX}/system.reg" ]]; then
      info "✓ Wine prefix initialized: ${WINEPREFIX}"
    else
      error "Wine prefix initialization failed — system.reg not found"
      return 1
    fi
  else
    info "✓ Wine prefix ready: ${WINEPREFIX}"
  fi
}

update_server() {
  if [[ "${UPDATE_ON_START}" != "1" ]]; then
    warn "Auto-update disabled (UPDATE_ON_START=${UPDATE_ON_START})"
    return 0
  fi

  local steamcmd
  if ! steamcmd="$(resolve_steamcmd)"; then
    error "SteamCMD not found"
    exit 1
  fi

  log "Updating/Installing Enshrouded Dedicated Server via SteamCMD..."
  local attempt=1
  local success=0

  while [[ $attempt -le $STEAMCMD_RETRIES ]]; do
    info "SteamCMD attempt ${attempt}/${STEAMCMD_RETRIES}..."
    if "${steamcmd}" \
      +@sSteamCmdForcePlatformType windows \
      +@sSteamCmdForcePlatformBitness 64 \
      +force_install_dir "${SERVER_DIR}" \
      +login anonymous \
      +app_update "${STEAMAPPID}" validate \
      +quit; then
      success=1
      break
    fi
    warn "SteamCMD attempt ${attempt} failed."
    attempt=$((attempt + 1))
    [[ $attempt -le $STEAMCMD_RETRIES ]] && sleep 5
  done

  if [[ $success -eq 1 ]]; then
    info "✓ SteamCMD update completed"
  else
    if [[ -f "${SERVER_DIR}/enshrouded_server.exe" ]]; then
      warn "SteamCMD failed after ${STEAMCMD_RETRIES} attempts, but existing server binary found. Continuing startup..."
    else
      error "SteamCMD failed after ${STEAMCMD_RETRIES} attempts and no server binary is installed."
      exit 1
    fi
  fi
}

verify_installation() {
  log "Verifying server installation..."
  local server_exe="${SERVER_DIR}/enshrouded_server.exe"
  if [[ ! -f "${server_exe}" ]]; then
    error "Server executable not found: ${server_exe}"
    exit 1
  fi
  info "✓ Found executable: ${server_exe}"
}

graceful_shutdown() {
  if [[ "${SHUTTING_DOWN}" -eq 1 ]]; then
    return 0
  fi
  SHUTTING_DOWN=1

  log "Received shutdown signal — flushing world saves and stopping server..."
  if [[ -n "${SERVER_PID}" ]] && kill -0 "${SERVER_PID}" 2>/dev/null; then
    kill -INT "${SERVER_PID}" 2>/dev/null || kill -TERM "${SERVER_PID}" 2>/dev/null || true
  fi
  pkill -INT -f enshrouded_server.exe >/dev/null 2>&1 || true

  if command -v wineserver >/dev/null 2>&1; then
    wineserver -w 2>/dev/null || true
  fi

  pkill -TERM Xvfb >/dev/null 2>&1 || true
  log "✓ Server stopped cleanly."
  exit 0
}

start_server() {
  log "Starting Enshrouded Dedicated Server..."
  cd "${SERVER_DIR}" || exit 1

  local wine_bin
  wine_bin="$(resolve_wine)" || { error "Wine missing at runtime"; exit 1; }

  info "Wine:       ${wine_bin}"
  info "Display:    ${DISPLAY}"
  info "WINEPREFIX: ${WINEPREFIX}"
  log "Server is launching! Watch below for '[Session] 'HostOnline' (up)'!"

  "${wine_bin}" "${SERVER_DIR}/enshrouded_server.exe" &
  SERVER_PID=$!

  wait "${SERVER_PID}"
  local exit_code=$?
  if [[ "${SHUTTING_DOWN}" -eq 0 ]]; then
    warn "Server process exited with code ${exit_code}"
  fi
  exit "${exit_code}"
}

main() {
  print_banner
  trap graceful_shutdown SIGTERM SIGINT SIGHUP

  preflight_checks
  create_directories
  start_xvfb
  init_wine
  update_server
  verify_installation
  configure_server
  start_server
}

main "$@"