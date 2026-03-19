#!/usr/bin/env bash
set -e

echo "[INIT] Fixing volume ownership..."
for dir in /home/steam/server /home/steam/config /home/steam/.wine; do
  if [[ -d "$dir" ]]; then
    if [[ "$(stat -c '%u' "$dir")" != "999" ]]; then
      echo "[INIT] chown 999:999 $dir"
      chown -R 999:999 "$dir"
    fi
  fi
done

echo "[INIT] Dropping to steam user..."
exec gosu steam /home/steam/entrypoint.sh "$@"