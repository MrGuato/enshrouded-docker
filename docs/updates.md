---
title: Updates
layout: default
nav_order: 4
---

# Updates

Two things update independently: the container image (Docker) and the game files (SteamCMD).

## Game updates (the frequent one)

Enshrouded patches land on Steam. Because `UPDATE_ON_START=true`, every container start runs `app_update 2278520 validate` for the Windows build and pulls the new version. So after a patch:

```bash
./enshrouded restart
```

Players need the matching client version, so coordinate the restart with them.

## Image updates

```bash
./enshrouded update
```

That pulls the latest image from GHCR, recreates the container and lets SteamCMD validate the game files on start. Saves and config persist because they live in `./enshrouded-config`.

The image is rebuilt every Monday so Ubuntu and Wine security fixes arrive without waiting for a release.

## Automatic image updates

`docker-compose.yaml` includes Watchtower, which checks GHCR every day at 05:00 (in the `TZ` from `.env`, UTC if unset) and recreates the Enshrouded container when a new image for your tag exists. It only touches containers with the `com.centurylinklabs.watchtower.enable=true` label, which the Enshrouded service carries.

Watchtower's `--schedule` takes six cron fields with seconds first, so the compose file uses `0 0 5 * * *`. The usual five-field `0 5 * * *` would run every hour at minute 5.

Remove the `watchtower` service from the compose file if you prefer manual updates. If you already run Watchtower for other containers, remove this one and let yours pick up the label.

## Pin a release

`latest` follows `main`. To update only when you choose, pin a release:

```ini
IMAGE_TAG=1.0.0
```

```bash
./enshrouded update
```

Image tags drop the `v` from the git tag: release `v1.0.0` publishes `1.0.0` and `1.0`. Pinning `1.0` picks up patch releases (1.0.1, 1.0.2) but never 1.1. Watchtower follows whatever tag you pin. Release notes are on the [releases page](https://github.com/MrGuato/enshrouded-docker/releases) and in the [changelog](https://github.com/MrGuato/enshrouded-docker/blob/main/CHANGELOG.md).

## Skip SteamCMD on start

For hosts with restricted internet:

```ini
UPDATE_ON_START=false
```

The container starts the existing game files without contacting Steam. To update later, flip it back and run `./enshrouded update`.

## Scheduled restarts

A nightly restart picks up game patches and clears memory. It disconnects anyone still playing, so pick an hour when your group is asleep:

```cron
10 5 * * * cd /home/you/enshrouded-docker && ./enshrouded restart >> logs/restart.log 2>&1
```
