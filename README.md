[![Made With Love](https://img.shields.io/badge/Made%20with%20%E2%9D%A4%EF%B8%8F-by%20Jonathan-red)](https://github.com/MrGuato)
[![pages-build-deployment](https://github.com/MrGuato/enshrouded-docker/actions/workflows/pages/pages-build-deployment/badge.svg)](https://github.com/MrGuato/enshrouded-docker/actions/workflows/pages/pages-build-deployment)
[![Build & Push (GHCR)](https://github.com/MrGuato/enshrouded-docker/actions/workflows/docker-ghcr.yml/badge.svg)](https://github.com/MrGuato/enshrouded-docker/actions/workflows/docker-ghcr.yml)
[![GHCR](https://img.shields.io/badge/GHCR-container%20registry-blue)](https://github.com/mrguato/enshrouded-docker/pkgs/container)
![Visitors](https://visitor-badge.laobi.icu/badge?page_id=mrguato.enshrouded-docker)

# Enshrouded Dedicated Server — Docker

> **Set-and-forget Enshrouded Dedicated Server. Pulls the latest game build on every start via SteamCMD. No rebuilds. No manual updates. No drift.**

---

## Why This Exists

Most Enshrouded server setups fall into one of these traps:

- ❌ Manual installs that drift over time
- ❌ Docker images that go stale between Steam updates
- ❌ Containers that need a full rebuild just to patch the game
- ❌ Root containers, brittle startup logic, or unclear persistence

This project fixes all of that.

### Core Idea

> **The image is immutable. The game server is not.**

The container ships **Wine + SteamCMD**. On every start, it pulls the latest Enshrouded Dedicated Server (AppID `2278520`) before launching — so you're always running the current version without touching the image.

---

## Quick Start (Fresh Ubuntu VM)

The fastest path from zero to running server:

```bash
curl -fsSL https://raw.githubusercontent.com/MrGuato/enshrouded-docker/main/setup.sh | bash
```

`setup.sh` installs Docker if missing, then pulls and starts the container. On first run it will prompt you to log out and back in if Docker was just installed — then run it again.

---

## Manual Setup (Docker Compose)

If you already have Docker installed:

```bash
git clone https://github.com/MrGuato/enshrouded-docker
cd enshrouded-docker
docker compose up -d
```

Watch the first-run download (~6 GB):

```bash
docker compose logs -f
```

### docker-compose.yml

```yaml
services:
  enshrouded:
    image: ghcr.io/mrguato/enshrouded-docker:latest
    build: .
    container_name: enshrouded-server
    restart: unless-stopped
    ports:
      - "15637:15637/udp"
      - "27015:27015/udp"
    environment:
      UPDATE_ON_START: "1"
      SERVER_NAME: "My Enshrouded Server"
      SERVER_SLOTS: "16"
      SERVER_PASSWORD: ""        # leave empty for no password
      GAME_PORT: "15637"
      QUERY_PORT: "27015"
      WINEPREFIX: "/home/steam/.wine"
    volumes:
      - ./enshrouded-config:/home/steam/config    # saves, logs, config
      - ./enshrouded-server:/home/steam/server    # game files (cached)
      - ./enshrouded-wine:/home/steam/.wine       # Wine prefix (cached)
```

---

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `UPDATE_ON_START` | `1` | Pull latest game build on startup (`0` to skip) |
| `SERVER_NAME` | `Enshrouded Docker Server` | Server name shown in browser |
| `SERVER_SLOTS` | `16` | Max player slots |
| `SERVER_PASSWORD` | *(empty)* | Leave empty for public server |
| `GAME_PORT` | `15637` | UDP game port |
| `QUERY_PORT` | `27015` | UDP query/discovery port |
| `WINEPREFIX` | `/home/steam/.wine` | Wine prefix path |

---

## Persistence Model

State lives entirely in mounted volumes — survive rebuilds, image upgrades, and host migrations:

```
enshrouded-config/
 ├─ savegame/          ← world saves
 ├─ logs/              ← server logs
 └─ enshrouded_server.json   ← server config

enshrouded-server/    ← game binaries (SteamCMD install target)
enshrouded-wine/      ← Wine prefix
```

Persisting `enshrouded-server/` means SteamCMD only downloads what changed, not the full ~6 GB on every restart.

---

## Updating

To pull the latest published image:

```bash
docker compose pull
docker compose up -d
```

Your world data is untouched. The container re-creates from the new image and SteamCMD handles any game binary updates on startup.

---

## Ports

| Port | Protocol | Purpose |
|---|---|---|
| `15637` | UDP | Game traffic |
| `27015` | UDP | Server discovery / query |

Open both on your host firewall and forward them on your router if hosting publicly.

---

## Architecture

```
Host (Ubuntu VM)
┌─────────────────────────────────────────────────┐
│  docker compose up                              │
└───────────────┬─────────────────────────────────┘
                │
                ▼
  Container: enshrouded-server
┌─────────────────────────────────────────────────┐
│  entrypoint.sh                                  │
│   ├─ Xvfb :99 (headless display for Wine)       │
│   ├─ SteamCMD → app_update 2278520 validate     │
│   └─ wine enshrouded_server.exe                 │
└───────────┬─────────────────────────────────────┘
            │
  ┌─────────┴──────────┐
  ▼                    ▼
UDP 15637/27015     ./enshrouded-*/  (volume mounts)
```

---

## Security

- Runs as non-root user (`steam`, uid 999)
- No privileged mode
- Only required UDP ports exposed
- No inbound management interfaces
- All state in explicit volume mounts — nothing hidden in the container layer

---

## CI/CD

A GitHub Actions pipeline builds and pushes images to GHCR on every push to `main`, on a daily schedule, and on manual dispatch. Published tags: `latest`, `sha-<commit>`, `YYYYMMDD`, and SemVer (`v1.x.x`) when tagged.

---

## Troubleshooting

**Server not visible in-game**
- Verify UDP 15637 and 27015 are open on the host firewall
- Confirm router port forwarding if self-hosted
- `docker ps` to verify ports are published

**Container crash-loops on startup**
- `docker compose logs -f` — look for SteamCMD or Wine errors
- Steam-side failures are often transient; restart the container and try again
- If `UPDATE_ON_START=1` is set and SteamCMD can't reach Steam, the container will exit rather than start a stale server

**Permission errors on volume directories**
```bash
sudo chown -R $USER:$USER ./enshrouded-config ./enshrouded-server ./enshrouded-wine
```

---

## Philosophy

> Treat game servers like production services.

Automated, reproducible, observable, easy to reason about. The same mindset that makes this a good game server setup makes it a good pattern for anything else you run.