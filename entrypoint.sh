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

# New toggles
FORCE_CONFIG_REWRITE="${FORCE_CONFIG_REWRITE:-0}"   # 1 = always rewrite JSON from env
RESET_WINEPREFIX="${RESET_WINEPREFIX:-0}"           # 1 = delete and recreate WINEPREFIX on boot

WINEPREFIX="${WINEPREFIX:-/home/steam/.wine}"

# Make sure perms are correct for mounted volumes
mkdir -p "${EN_DIR}"
chown -R steam:steam "${EN_DIR}"

# Make sure Wine prefix is sane
mkdir -p "${WINEPREFIX}"
chown -R steam:steam "${WINEPREFIX}"

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

write_config_from_env() {
  local cfg="${EN_DIR}/enshrouded_server.json"
  echo "[+] Writing ${cfg} from env..."
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

write_config_if_missing() {
  local cfg="${EN_DIR}/enshrouded_server.json"
  if [[ -f "${cfg}" && "${FORCE_CONFIG_REWRITE}" != "1" ]]; then
    echo "[=] Found existing config: ${cfg}"
    return
  fi
  write_config_from_env
}

apply_env_overrides() {
  local cfg="${EN_DIR}/enshrouded_server.json"
  [[ -f "${cfg}" ]] || return

  # If you want env vars to always override even when JSON exists,
  # keep FORCE_CONFIG_REWRITE=1 OR do this patching.
  echo "[+] Applying env overrides to ${cfg} (if set)..."

  python3 - "$cfg" <<'PY'
import json, os, sys

cfg = sys.argv[1]
with open(cfg, "r", encoding="utf-8") as f:
    data = json.load(f)

def maybe_set(key, env_name, cast=None):
    val = os.environ.get(env_name, "")
    if val == "":
        return
    if cast:
        val = cast(val)
    data[key] = val

maybe_set("name", "SERVER_NAME")
maybe_set("password", "SERVER_PASSWORD")
maybe_set("gamePort", "PORT", int)
maybe_set("queryPort", "STEAM_PORT", int)
maybe_set("slotCount", "SERVER_SLOTS", int)

with open(cfg, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

  chown steam:steam "${cfg}"
}

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
apply_env_overrides
ensure_appid_file

echo "[+] Starting Enshrouded server..."
cd "${EN_DIR}"

exec gosu steam bash -lc "
  set -e

  export WINEPREFIX='${WINEPREFIX}'
  export WINEDEBUG='-all'
  export XDG_RUNTIME_DIR=/tmp/runtime-steam
  mkdir -p \$XDG_RUNTIME_DIR
  chmod 700 \$XDG_RUNTIME_DIR

  if [[ '${RESET_WINEPREFIX}' == '1' ]]; then
    echo '[!] RESET_WINEPREFIX=1 — resetting Wine prefix'
    rm -rf \"\$WINEPREFIX\"
    mkdir -p \"\$WINEPREFIX\"
  fi

  # Ensure ownership (important if volume/previous runs created root-owned files)
  chown -R steam:steam \"\$WINEPREFIX\"

  # Headless X server for Wine
  Xvfb :0 -screen 0 1024x768x16 >/dev/null 2>&1 &
  export DISPLAY=:0

  echo '[=] Wine binary:' \$(command -v wine || true)
  wine --version

  # Initialize prefix (creates kernel32/etc) - prevents some c0000135 situations
  wineboot -u || true

  exec wine enshrouded_server.exe
"
