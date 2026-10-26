#!/usr/bin/env bash
# Restore the world saves and server config from a tarball made by scripts/backup.sh.
# Usage: ./enshrouded restore ./backups/enshrouded-2026-10-25-0930.tar.gz
set -euo pipefail

cd "$(dirname "$0")/.."

ARCHIVE="${1:-}"
DOCKER="${DOCKER:-docker}"

if [ -z "$ARCHIVE" ] || [ ! -f "$ARCHIVE" ]; then
    echo "Usage: $0 <backup-archive.tar.gz>"
    echo "Example: $0 ./backups/enshrouded-2026-10-25-0930.tar.gz"
    exit 1
fi

echo "[restore] This overwrites enshrouded-config/savegame and enshrouded_server.json with the archive contents."
read -r -p "[restore] Continue? [y/N] " answer
case "${answer,,}" in y|yes) ;; *) echo "[restore] Aborted"; exit 1 ;; esac

echo "[restore] Stopping the server"
# shellcheck disable=SC2086
$DOCKER compose stop enshrouded

echo "[restore] Extracting $ARCHIVE"
if ! tar -xzf "$ARCHIVE"; then
    echo "[restore] ERROR: extraction failed. If ./enshrouded-config is root-owned, run this with sudo."
    exit 1
fi

echo "[restore] Starting the server"
# shellcheck disable=SC2086
$DOCKER compose start enshrouded

echo "[restore] Done"
