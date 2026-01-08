#!/usr/bin/env bash
set -euo pipefail

STEAMCMDDIR="${STEAMCMDDIR:-/opt/steamcmd}"
EN_DIR="${EN_DIR:-/home/steam/enshrouded}"
APP_ID="${APP_ID:-2278520}"

PORT="${PORT:-15637}"
STEAM_PORT="${STEAM_PORT:-27015}"
SERVER_NAME="${SERVER_NAME:-Enshrouded Docker}"
SERVER_SLOTS="${SERVER_SLOTS:-16}"
SERVER_PASSWORD="${SERVER_PASSWORD:-}"
UPDATE_ON_START="${UPDATE_ON_START:-1}"

# Make sure perms are correct for mounted volumes
mkdir -p "${EN_DIR}"
chown -R steam:steam "${EN_DIR}"

update_server() {
  echo "[+] Updating Enshrouded dedicated server via SteamCMD (AppID: ${APP_ID})..."
  gosu steam bash -lc "
    ${STEAMCMDDIR}/steamcmd.sh \
      +@sSteamCmdForcePlatformType windows \
      +force_install_dir ${EN_DIR} \
      +login anonymous \
      +app_update ${APP_ID} validate \
      +quit
  "
}

write_config_if_missing() {
  local cfg="${EN_DIR}/enshrouded_server.json"
  if [[ -f "${cfg}" ]]; then
    echo "[=] Found existing config: ${cfg}"
    return
  fi

  echo "[+] No config found; generating ${cfg} from env..."
  # This is a minimal config; you can replace with a full schema later.
  cat > "${cfg}" <<EOF
{
  "name": "${SERVER_NAME}",
  "password": "${SERVER_PASSWORD}",
  "saveDirectory": "./savegame",
  "logDirectory": "./logs",
  "ip": "0.0.0.0",
  "gamePort": ${PORT},
  "queryPort": ${STEAM_PORT},
  "slotCount": ${SERVER_SLOTS}
}
EOF
  chown steam:steam "${cfg}"
}

# Some people hit wrong app id issues; ensure base game appid file exists.
# (Dedicated server is 2278520, but runtime sometimes expects 1203620.)
ensure_appid_file() {
  echo "1203620" > "${EN_DIR}/steam_appid.txt"
  chown steam:steam "${EN_DIR}/steam_appid.txt"
}

if [[ "${UPDATE_ON_START}" == "1" ]]; then
  update_server
else
  echo "[=] UPDATE_ON_START=0 — skipping SteamCMD update"
fi

write_config_if_missing
ensure_appid_file

echo "[+] Starting Enshrouded server..."
cd "${EN_DIR}"

# Wine needs an X server; use Xvfb for headless
exec gosu steam bash -lc "
  set -e
  Xvfb :0 -screen 0 1024x768x16 >/dev/null 2>&1 &
  export DISPLAY=:0

  echo '[=] Wine binary:' \$(command -v wine || true)
  wine --version

  exec wine enshrouded_server.exe
"
