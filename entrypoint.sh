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

# Toggles
FORCE_CONFIG_REWRITE="${FORCE_CONFIG_REWRITE:-0}"   # 1 = always rewrite JSON from env
RESET_WINEPREFIX="${RESET_WINEPREFIX:-0}"           # 1 = delete and recreate WINEPREFIX on boot

WINEPREFIX="${WINEPREFIX:-/home/steam/.wine}"
WINEARCH="${WINEARCH:-win64}"
WINEDEBUG="${WINEDEBUG:--all}"
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-steam}"

# ---- preflight dirs + perms (host volumes often come in root-owned) ----
mkdir -p "${EN_DIR}" "${WINEPREFIX}"
chown -R steam:steam "${EN_DIR}" "${WINEPREFIX}" || true

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
  chown steam:steam "${cfg}" || true
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

  # Only patch if python3 exists; otherwise skip safely
  if ! command -v python3 >/dev/null 2>&1; then
    echo "[!] python3 not found; skipping env override patching"
    return
  fi

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

  chown steam:steam "${cfg}" || true
}

ensure_appid_file() {
  # IMPORTANT: match the APP_ID you installed
  echo "${APP_ID}" > "${EN_DIR}/steam_appid.txt"
  chown steam:steam "${EN_DIR}/steam_appid.txt" || true
}

# ---- do update ----
if [[ "${UPDATE_ON_START}" == "1" ]]; then
  update_server
else
  echo "[=] UPDATE_ON_START=0 — skipping SteamCMD update"
fi

# ---- config ----
write_config_if_missing
apply_env_overrides
ensure_appid_file

echo "[+] Starting Enshrouded server..."
cd "${EN_DIR}"

exec gosu steam bash -lc "
  set -euo pipefail

  export WINEPREFIX='${WINEPREFIX}'
  export WINEARCH='${WINEARCH}'
  export WINEDEBUG='${WINEDEBUG}'
  export XDG_RUNTIME_DIR='${XDG_RUNTIME_DIR}'
  mkdir -p \"\$XDG_RUNTIME_DIR\"
  chmod 700 \"\$XDG_RUNTIME_DIR\"

  # If requested, reset prefix SAFELY (kill wineserver first)
  if [[ '${RESET_WINEPREFIX}' == '1' ]]; then
    echo '[!] RESET_WINEPREFIX=1 — resetting Wine prefix (safe)'
    wineserver -k || true
    rm -rf \"\$WINEPREFIX\"
    mkdir -p \"\$WINEPREFIX\"
  fi

  # Ensure ownership (important if volume/previous runs created root-owned files)
  chown -R steam:steam \"\$WINEPREFIX\" || true

  # Headless X server for Wine
  Xvfb :0 -screen 0 1024x768x16 >/dev/null 2>&1 &
  export DISPLAY=:0

  echo '[=] Wine binary:' \$(command -v wine || true)
  wine --version

  # Idempotent prefix initialization (mbround-style behavior)
  INIT_MARKER=\"\$WINEPREFIX/.initialized\"
  if [[ ! -f \"\$INIT_MARKER\" ]]; then
    echo '[+] First run: initializing Wine prefix...'
    wineserver -k || true
    wineboot -u || true
    wineserver -w || true
    touch \"\$INIT_MARKER\"
  else
    echo '[=] Wine prefix already initialized.'
  fi

  exec wine enshrouded_server.exe
"
