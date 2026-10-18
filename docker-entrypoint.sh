#!/usr/bin/env bash
set -euo pipefail

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

if [[ "$(id -u)" -eq 0 ]]; then
  echo "[INIT] Configuring steam user (PUID=${PUID}, PGID=${PGID})..."

  if [[ "$(id -g steam)" != "${PGID}" ]]; then
    groupmod -o -g "${PGID}" steam
  fi

  if [[ "$(id -u steam)" != "${PUID}" ]]; then
    usermod -o -u "${PUID}" -g "${PGID}" steam
  fi

  echo "[INIT] Ensuring directory existence and ownership..."
  mkdir -p /home/steam/server /home/steam/config /home/steam/.wine /opt/steamcmd

  for dir in /home/steam/server /home/steam/config /home/steam/.wine /opt/steamcmd; do
    if [[ -d "$dir" ]]; then
      current_uid="$(stat -c '%u' "$dir" 2>/dev/null || echo "")"
      current_gid="$(stat -c '%g' "$dir" 2>/dev/null || echo "")"
      if [[ "$current_uid" != "${PUID}" || "$current_gid" != "${PGID}" ]]; then
        echo "[INIT] Fixing ownership (${PUID}:${PGID}) on $dir..."
        chown -R "${PUID}:${PGID}" "$dir"
      fi
    fi
  done

  chown "${PUID}:${PGID}" /home/steam /home/steam/entrypoint.sh 2>/dev/null || true

  # Clean up any stale Xvfb lock files from previous container runs
  DISPLAY_NUM="${DISPLAY:-:99}"
  DISPLAY_NUM="${DISPLAY_NUM#:}"
  rm -f "/tmp/.X${DISPLAY_NUM}-lock" "/tmp/.X11-unix/X${DISPLAY_NUM}" 2>/dev/null || true

  echo "[INIT] Dropping privileges to steam user..."
  exec gosu steam /home/steam/entrypoint.sh "$@"
else
  exec /home/steam/entrypoint.sh "$@"
fi