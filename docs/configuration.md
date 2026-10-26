---
title: Configuration
layout: default
nav_order: 3
---

# Configuration

Every setting lives in `.env`. After a change, apply it with:

```bash
./enshrouded update
```

(`./enshrouded restart` reuses the old container environment; `update` recreates the container so it picks up `.env`.)

## How settings reach the game

Enshrouded reads its settings from `enshrouded_server.json`. On every start the entrypoint writes the values from `.env` into that file and leaves everything else in it alone, including `gameSettings`, bans and keys it does not know about.

- **Passwords** are only written when at least one password is set in `.env`. Leave all four empty and whatever is in the JSON stays.
- **The preset** is never changed while the JSON says `Custom`, so hand-tuned difficulty settings survive a restart.
- To manage the JSON completely by hand, set `SYNC_CONFIG_ON_START=false`. Stop the server before editing it, because Enshrouded can write to it while running.

The file lives at `enshrouded-config/enshrouded_server.json` and is kept at mode 600 because it holds the passwords.

## Server

| Variable | Default | What it does |
| -------- | ------- | ------------ |
| `SERVER_NAME` | `My Enshrouded Server` | Name in the in-game server browser |
| `SERVER_SLOTS` | `16` | Maximum players, 1 to 16 |
| `QUERY_PORT` | `15637` | UDP port for players and the server browser |
| `TZ` | `UTC` | Time zone for logs and Watchtower's schedule |

## Passwords and roles

Use one password for everyone, or roles. If any role password is set, `SERVER_PASSWORD` is ignored.

| Variable | Role | Rights |
| -------- | ---- | ------ |
| `SERVER_PASSWORD` | Default | Everything, including kick and ban |
| `ADMIN_PASSWORD` | Admin | Kick and ban, build, open chests |
| `FRIEND_PASSWORD` | Friend | Build and open chests |
| `GUEST_PASSWORD` | Guest | Explore and fight, no building or chests |

Players pick their role by the password they type when joining. With no password at all, anyone who finds the server can join and edit your bases; the container logs a warning when that is the case.

Passwords with `$`, `#`, spaces or double quotes need single quotes in `.env` (`SERVER_PASSWORD='p@ss $word'`). `./enshrouded setup` adds them for you.

## Game settings

| Variable | Default | What it does |
| -------- | ------- | ------------ |
| `GAME_SETTINGS_PRESET` | `Default` | `Default`, `Relaxed`, `Hard`, `Survival` or `Custom` |
| `ENABLE_VOICE_CHAT` | `false` | In-game voice chat |
| `VOICE_CHAT_MODE` | `Proximity` | `Proximity` or `Global` |
| `ENABLE_TEXT_CHAT` | `false` | In-game text chat |

For individual difficulty settings (enemy health, resource drops, day length and so on), set `GAME_SETTINGS_PRESET=Custom`, stop the server, and add or edit the `gameSettings` block in `enshrouded_server.json`. Keen Games' dedicated server documentation lists every key and its allowed range. The entrypoint never touches `gameSettings`.

## Container

| Variable | Default | What it does |
| -------- | ------- | ------------ |
| `IMAGE_REPOSITORY` | `ghcr.io/mrguato/enshrouded-docker` | Where the image comes from |
| `IMAGE_TAG` | `latest` | `latest` follows `main`; pin a release like `1.0.0` |
| `CONTAINER_NAME` | `enshrouded-server` | Name of the container |
| `PUID` / `PGID` | `1000` / `1000` | User and group the server runs as. Match the owner of the folders. `PUID=0` runs as root |
| `UPDATE_ON_START` | `true` | Validate and update the game through SteamCMD on every start |
| `SYNC_CONFIG_ON_START` | `true` | Write `.env` settings into `enshrouded_server.json` on start |
| `STOP_TIMEOUT` | `90` | Seconds the server gets to exit after Ctrl+C when the container stops |
| `STEAMCMD_RETRIES` | `3` | SteamCMD attempts before starting with what is installed |

`true`/`false` and `1`/`0` both work for the switches.

## Volumes

```text
enshrouded-docker/
+-- enshrouded-config/            Back this up
|   +-- enshrouded_server.json    Server config (passwords inside, mode 600)
|   +-- savegame/                 World saves
|   +-- logs/                     Server logs
+-- enshrouded-server/            Game files from SteamCMD (~6 GB, reproducible)
+-- enshrouded-wine/              Wine prefix (reproducible)
+-- backups/                      Tarballs from ./enshrouded backup
```

Inside the container, Enshrouded writes `./savegame` and `./logs` next to its executable. The entrypoint links both into `enshrouded-config/`, and moves folders left behind by older setups over on the next start.

## Ports

| Port | Protocol | What for |
| ---- | -------- | -------- |
| 15637 (`QUERY_PORT`) | UDP | Players and the server browser. Forward this one |
| 27015 | UDP | Steam. Mapped by the compose file, no forward needed |
