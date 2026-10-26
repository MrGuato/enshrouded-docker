#!/usr/bin/env bash
# Runs as root: aligns the in-container user with PUID/PGID, fixes ownership of the
# bind-mounted volumes, applies TZ, clears stale Xvfb locks, then drops privileges and
# runs entrypoint.sh. PUID=0 keeps the server running as root.
set -euo pipefail

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
CONFIG_DIR="${CONFIG_DIR:-/home/steam/config}"
SERVER_DIR="${SERVER_DIR:-/home/steam/server}"
STEAMCMD_DIR="${STEAMCMD_DIR:-/opt/steamcmd}"
WINEPREFIX="${WINEPREFIX:-/home/steam/.wine}"

log() { echo "[enshrouded] $*"; }

if [ "$(id -u)" -ne 0 ]; then
    # Container was started with --user; nothing to fix.
    exec /usr/local/bin/entrypoint.sh "$@"
fi

if [ -n "${TZ:-}" ] && [ -f "/usr/share/zoneinfo/$TZ" ]; then
    ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime
    echo "$TZ" > /etc/timezone
fi

# A container that was killed leaves Xvfb's lock behind, and the next Xvfb refuses to start.
display_num="${DISPLAY:-:99}"
display_num="${display_num#:}"
rm -f "/tmp/.X${display_num}-lock" "/tmp/.X11-unix/X${display_num}"

mkdir -p "$CONFIG_DIR" "$SERVER_DIR" "$WINEPREFIX"

if [ "$PUID" = "0" ]; then
    log "PUID=0, running the server as root"
    exec /usr/local/bin/entrypoint.sh "$@"
fi

if [ "$(id -g steam)" != "$PGID" ]; then groupmod -o -g "$PGID" steam; fi
if [ "$(id -u steam)" != "$PUID" ]; then usermod -o -u "$PUID" steam; fi

# chown only when the top-level owner is wrong (first start, or files left by an earlier root
# container); recursing over ~6 GB of game files on every start would be wasteful.
for dir in "$CONFIG_DIR" "$SERVER_DIR" "$WINEPREFIX" "$STEAMCMD_DIR" /home/steam; do
    if [ -d "$dir" ] && { [ "$(stat -c '%u' "$dir")" != "$PUID" ] || [ "$(stat -c '%g' "$dir")" != "$PGID" ]; }; then
        log "Fixing ownership of $dir -> $PUID:$PGID"
        chown -R "$PUID:$PGID" "$dir"
    fi
done

exec gosu steam /usr/local/bin/entrypoint.sh "$@"
