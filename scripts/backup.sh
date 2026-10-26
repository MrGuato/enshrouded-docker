#!/usr/bin/env bash
# Snapshot everything that cannot be re-downloaded: the world saves and the server config.
# Usage: ./enshrouded backup      (or scripts/backup.sh)
#   BACKUP_DIR      where tarballs go            (default ./backups)
#   RETENTION_DAYS  delete tarballs older than   (default 14)
set -euo pipefail

cd "$(dirname "$0")/.."

BACKUP_DIR=${BACKUP_DIR:-./backups}
RETENTION_DAYS=${RETENTION_DAYS:-14}
TIMESTAMP=$(date +%F-%H%M)
ARCHIVE="$BACKUP_DIR/enshrouded-$TIMESTAMP.tar.gz"

mkdir -p "$BACKUP_DIR"

if [ ! -d enshrouded-config/savegame ]; then
    echo "[backup] enshrouded-config/savegame not found, nothing to back up (has the server started once?)"
    exit 1
fi

# The game files and Wine prefix are reproducible and intentionally excluded.
ITEMS=(enshrouded-config/savegame)
if [ -f enshrouded-config/enshrouded_server.json ]; then ITEMS+=(enshrouded-config/enshrouded_server.json); fi

# The config holds the server passwords, so the archive is only readable by its owner.
umask 077
echo "[backup] Creating $ARCHIVE"
if ! tar --warning=no-file-changed -czf "$ARCHIVE" "${ITEMS[@]}"; then
    echo "[backup] ERROR: tar failed. If ./enshrouded-config is root-owned (PUID=0), run: sudo ./enshrouded backup"
    rm -f "$ARCHIVE"
    exit 1
fi
gzip -t "$ARCHIVE"

echo "[backup] Pruning archives older than $RETENTION_DAYS days"
find "$BACKUP_DIR" -maxdepth 1 -name 'enshrouded-*.tar.gz' -mtime "+$RETENTION_DAYS" -delete

ls -lh "$ARCHIVE"
echo "[backup] Done"
