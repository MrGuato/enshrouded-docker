#!/usr/bin/env bash
# Healthy as soon as the Enshrouded server process is running under Wine. The start period
# covers the first SteamCMD download (~6 GB) that happens before it starts.
set -euo pipefail

if pgrep -f 'enshrouded_server\.exe' >/dev/null 2>&1; then
    exit 0
fi
exit 1
