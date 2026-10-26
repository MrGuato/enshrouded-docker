#!/usr/bin/env bash
# Runs as the steam user (or root when PUID=0): validates settings, installs/updates the game
# through SteamCMD, writes enshrouded_server.json from the environment, starts the server under
# Wine and gives it a clean shutdown when the container stops.
set -euo pipefail

STEAM_APP_ID="${STEAM_APP_ID:-2278520}"
SERVER_DIR="${SERVER_DIR:-/home/steam/server}"
CONFIG_DIR="${CONFIG_DIR:-${SERVER_CONFIG_DIR:-/home/steam/config}}"
STEAMCMD_DIR="${STEAMCMD_DIR:-/opt/steamcmd}"
CONFIG_FILE="$CONFIG_DIR/enshrouded_server.json"
SAVEGAME_DIR="$CONFIG_DIR/savegame"
LOG_DIR="$CONFIG_DIR/logs"

UPDATE_ON_START="${UPDATE_ON_START:-true}"
SYNC_CONFIG_ON_START="${SYNC_CONFIG_ON_START:-true}"
STEAMCMD_RETRIES="${STEAMCMD_RETRIES:-3}"
STOP_TIMEOUT="${STOP_TIMEOUT:-90}"

SERVER_NAME="${SERVER_NAME:-My Enshrouded Server}"
SERVER_SLOTS="${SERVER_SLOTS:-16}"
SERVER_PASSWORD="${SERVER_PASSWORD:-}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
FRIEND_PASSWORD="${FRIEND_PASSWORD:-}"
GUEST_PASSWORD="${GUEST_PASSWORD:-}"
SERVER_IP="${SERVER_IP:-0.0.0.0}"
QUERY_PORT="${QUERY_PORT:-15637}"
GAME_PORT="${GAME_PORT:-$QUERY_PORT}"
ENABLE_VOICE_CHAT="${ENABLE_VOICE_CHAT:-false}"
VOICE_CHAT_MODE="${VOICE_CHAT_MODE:-Proximity}"
ENABLE_TEXT_CHAT="${ENABLE_TEXT_CHAT:-false}"
GAME_SETTINGS_PRESET="${GAME_SETTINGS_PRESET:-Default}"

export WINEPREFIX="${WINEPREFIX:-$HOME/.wine}"
export WINEARCH="${WINEARCH:-win64}"
export WINEDEBUG="${WINEDEBUG:--all}"
export DISPLAY="${DISPLAY:-:99}"

SERVER_PID=""
XVFB_PID=""

log() { echo "[enshrouded] $*"; }
die() { echo "[enshrouded] ERROR: $*" >&2; exit 1; }
is_true() { case "${1,,}" in 1|true|yes|on) return 0 ;; *) return 1 ;; esac; }
json_bool() { if is_true "$1"; then echo true; else echo false; fi; }

validate() {
    [[ "$SERVER_SLOTS" =~ ^[0-9]+$ ]] && [ "$SERVER_SLOTS" -ge 1 ] && [ "$SERVER_SLOTS" -le 16 ] \
        || die "SERVER_SLOTS must be a number from 1 to 16"
    [[ "$QUERY_PORT" =~ ^[0-9]+$ ]] || die "QUERY_PORT must be a number"
    [[ "$GAME_PORT" =~ ^[0-9]+$ ]]  || die "GAME_PORT must be a number"
    [[ "$STOP_TIMEOUT" =~ ^[0-9]+$ ]] || die "STOP_TIMEOUT must be a number of seconds"
    case "$VOICE_CHAT_MODE" in Proximity|Global) ;; *) die "VOICE_CHAT_MODE must be Proximity or Global" ;; esac
    case "$GAME_SETTINGS_PRESET" in
        Default|Relaxed|Hard|Survival|Custom) ;;
        *) die "GAME_SETTINGS_PRESET must be Default, Relaxed, Hard, Survival or Custom" ;;
    esac
    if [ -z "$SERVER_PASSWORD$ADMIN_PASSWORD$FRIEND_PASSWORD$GUEST_PASSWORD" ]; then
        log "WARNING: no password is set, anyone who finds the server can join and edit your bases"
    fi
}

update_server() {
    if ! is_true "$UPDATE_ON_START"; then
        log "UPDATE_ON_START=$UPDATE_ON_START, skipping SteamCMD"
        return
    fi
    [ -w "$SERVER_DIR" ] || die "$SERVER_DIR is not writable by $(id -un) (uid $(id -u)). Fix the owner of the ./enshrouded-server mount or set PUID/PGID to match it"

    # SteamCMD's first run self-updates and writes its config; without this warm-up the
    # very first app_update often fails with "Missing configuration".
    log "Initializing SteamCMD"
    "$STEAMCMD_DIR/steamcmd.sh" +quit >/dev/null 2>&1 || true

    local attempt rc
    for (( attempt = 1; attempt <= STEAMCMD_RETRIES; attempt++ )); do
        log "Installing / updating the Enshrouded dedicated server (AppID $STEAM_APP_ID), attempt $attempt of $STEAMCMD_RETRIES"
        rc=0
        "$STEAMCMD_DIR/steamcmd.sh" \
            +@sSteamCmdForcePlatformType windows \
            +@sSteamCmdForcePlatformBitness 64 \
            +force_install_dir "$SERVER_DIR" \
            +login anonymous \
            +app_update "$STEAM_APP_ID" validate \
            +quit || rc=$?
        if [ "$rc" -eq 0 ] && [ -f "$SERVER_DIR/enshrouded_server.exe" ]; then
            return
        fi
        log "WARNING: SteamCMD attempt $attempt failed (exit code $rc), retrying in 10s"
        sleep 10
    done
    log "WARNING: SteamCMD failed $STEAMCMD_RETRIES times; trying to start with whatever is installed"
}

# Enshrouded writes ./savegame and ./logs next to the executable. Point both at $CONFIG_DIR so
# saves live in the config volume, not in the game files. Folders from older setups are moved over.
link_persistent_dirs() {
    local name target
    mkdir -p "$SAVEGAME_DIR" "$LOG_DIR"
    for name in savegame logs; do
        target="$CONFIG_DIR/$name"
        if [ -d "$SERVER_DIR/$name" ] && [ ! -L "$SERVER_DIR/$name" ]; then
            log "Moving $SERVER_DIR/$name to $target"
            cp -rn "$SERVER_DIR/$name/." "$target/"
            rm -rf "${SERVER_DIR:?}/$name"
        fi
        ln -sfn "$target" "$SERVER_DIR/$name"
    done
}

user_groups_json() {
    if [ -n "$ADMIN_PASSWORD$FRIEND_PASSWORD$GUEST_PASSWORD" ]; then
        jq -n --arg admin "$ADMIN_PASSWORD" --arg friend "$FRIEND_PASSWORD" --arg guest "$GUEST_PASSWORD" '[
            (if $admin  != "" then {name: "Admin",  password: $admin,  canKickBan: true,  canAccessInventories: true,  canEditBase: true,  canExtendBase: true,  reservedSlots: 0} else empty end),
            (if $friend != "" then {name: "Friend", password: $friend, canKickBan: false, canAccessInventories: true,  canEditBase: true,  canExtendBase: true,  reservedSlots: 0} else empty end),
            (if $guest  != "" then {name: "Guest",  password: $guest,  canKickBan: false, canAccessInventories: false, canEditBase: false, canExtendBase: false, reservedSlots: 0} else empty end)
        ]'
    elif [ -n "$SERVER_PASSWORD" ]; then
        jq -n --arg pw "$SERVER_PASSWORD" \
            '[{name: "Default", password: $pw, canKickBan: true, canAccessInventories: true, canEditBase: true, canExtendBase: true, reservedSlots: 0}]'
    else
        echo '[]'
    fi
}

# Writes the .env values into enshrouded_server.json and leaves everything else in the file
# alone (gameSettings, bans, keys this script does not know about). Passwords and user groups
# are only touched when at least one password is set, and the preset is never changed while
# the file says "Custom", so hand-tuned difficulty settings survive.
configure_server() {
    local server_link="$SERVER_DIR/enshrouded_server.json" tmp="$CONFIG_FILE.tmp"

    if [ -f "$server_link" ] && [ ! -L "$server_link" ] && [ ! -f "$CONFIG_FILE" ]; then
        log "Moving $server_link to $CONFIG_FILE"
        mv "$server_link" "$CONFIG_FILE"
    fi

    local fresh=false
    if [ ! -f "$CONFIG_FILE" ] || ! jq empty "$CONFIG_FILE" >/dev/null 2>&1; then
        if [ -f "$CONFIG_FILE" ]; then
            log "WARNING: $CONFIG_FILE is not valid JSON, keeping it as $CONFIG_FILE.broken and writing a new one"
            mv "$CONFIG_FILE" "$CONFIG_FILE.broken"
        fi
        echo '{}' > "$CONFIG_FILE"
        fresh=true
    fi

    if [ "$fresh" = true ] || is_true "$SYNC_CONFIG_ON_START"; then
        local with_passwords=false
        if [ "$fresh" = true ] || [ -n "$SERVER_PASSWORD$ADMIN_PASSWORD$FRIEND_PASSWORD$GUEST_PASSWORD" ]; then
            with_passwords=true
        fi
        jq \
            --arg name "$SERVER_NAME" \
            --arg ip "$SERVER_IP" \
            --argjson queryPort "$QUERY_PORT" \
            --argjson gamePort "$GAME_PORT" \
            --argjson slotCount "$SERVER_SLOTS" \
            --arg voiceChatMode "$VOICE_CHAT_MODE" \
            --argjson enableVoiceChat "$(json_bool "$ENABLE_VOICE_CHAT")" \
            --argjson enableTextChat "$(json_bool "$ENABLE_TEXT_CHAT")" \
            --arg preset "$GAME_SETTINGS_PRESET" \
            --argjson withPasswords "$with_passwords" \
            --arg password "$SERVER_PASSWORD" \
            --argjson userGroups "$(user_groups_json)" \
            '.name = $name
             | .saveDirectory = "./savegame"
             | .logDirectory = "./logs"
             | .ip = $ip
             | .queryPort = $queryPort
             | .gamePort = $gamePort
             | .slotCount = $slotCount
             | .voiceChatMode = $voiceChatMode
             | .enableVoiceChat = $enableVoiceChat
             | .enableTextChat = $enableTextChat
             | .gameSettingsPreset = (if .gameSettingsPreset == "Custom" then "Custom" else $preset end)
             | if $withPasswords then .password = $password | .userGroups = $userGroups else . end' \
            "$CONFIG_FILE" > "$tmp"
        mv "$tmp" "$CONFIG_FILE"
        chmod 600 "$CONFIG_FILE"
        if [ "$fresh" = true ]; then log "Wrote $CONFIG_FILE"; else log "Synced .env settings into $CONFIG_FILE"; fi
    else
        log "SYNC_CONFIG_ON_START=$SYNC_CONFIG_ON_START, using $CONFIG_FILE as it is"
    fi

    ln -sfn "$CONFIG_FILE" "$server_link"
}

start_xvfb() {
    log "Starting the virtual display on $DISPLAY"
    Xvfb "$DISPLAY" -screen 0 1024x768x16 -nolisten tcp >/dev/null 2>&1 &
    XVFB_PID=$!
    sleep 2
    kill -0 "$XVFB_PID" 2>/dev/null || die "Xvfb failed to start on $DISPLAY"
}

init_wine() {
    if [ -f "$WINEPREFIX/system.reg" ]; then
        return
    fi
    log "Creating the Wine prefix in $WINEPREFIX (first start only)"
    wineboot --init >/dev/null 2>&1 || true
    wineserver --wait || true
    [ -f "$WINEPREFIX/system.reg" ] || die "Wine prefix initialization failed, $WINEPREFIX/system.reg is missing"
}

shutdown() {
    log "Shutdown requested, sending Ctrl+C to the server (waiting up to ${STOP_TIMEOUT}s for it to exit)"
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill -INT "$SERVER_PID" 2>/dev/null || true
        pkill -INT -f 'enshrouded_server\.exe' 2>/dev/null || true
        local i
        for (( i = 0; i < STOP_TIMEOUT; i++ )); do
            kill -0 "$SERVER_PID" 2>/dev/null || break
            sleep 1
        done
        if kill -0 "$SERVER_PID" 2>/dev/null; then
            log "Server did not exit within ${STOP_TIMEOUT}s, stopping Wine"
            wineserver -k 2>/dev/null || kill -KILL "$SERVER_PID" 2>/dev/null || true
        fi
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    wineserver -w 2>/dev/null || true
    if [ -n "$XVFB_PID" ]; then kill "$XVFB_PID" 2>/dev/null || true; fi
    log "Server stopped"
    exit 0
}

main() {
    log "Enshrouded Dedicated Server container by MrGuato, running as $(id -un) (uid $(id -u))"
    validate
    mkdir -p "$CONFIG_DIR" "$SERVER_DIR" "$WINEPREFIX"
    [ -w "$CONFIG_DIR" ] || die "$CONFIG_DIR is not writable by $(id -un) (uid $(id -u)). Fix the owner of the ./enshrouded-config mount or set PUID/PGID to match it"
    update_server
    [ -f "$SERVER_DIR/enshrouded_server.exe" ] || die "enshrouded_server.exe not found in $SERVER_DIR (SteamCMD download failed?)"
    link_persistent_dirs
    configure_server

    trap shutdown TERM INT
    start_xvfb
    init_wine

    local auth="open"
    if [ -n "$ADMIN_PASSWORD$FRIEND_PASSWORD$GUEST_PASSWORD" ]; then auth="role passwords"
    elif [ -n "$SERVER_PASSWORD" ]; then auth="password"; fi
    log "Starting: name='$SERVER_NAME' slots=$SERVER_SLOTS port=$QUERY_PORT/udp ($auth)"
    log "Saves: $SAVEGAME_DIR   Game files: $SERVER_DIR"
    log "Ready when the log shows: [Session] 'HostOnline' (up)"

    # Older WineHQ builds ship a separate wine64 loader; newer ones run 64-bit programs with wine.
    local wine_bin=wine
    if command -v wine64 >/dev/null 2>&1; then wine_bin=wine64; fi

    cd "$SERVER_DIR"
    "$wine_bin" "$SERVER_DIR/enshrouded_server.exe" &
    SERVER_PID=$!
    local rc=0
    wait "$SERVER_PID" || rc=$?
    log "Server exited with code $rc"
    exit "$rc"
}

main "$@"
