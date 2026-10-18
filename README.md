[![Made With Love](https://img.shields.io/badge/Made%20with%20%E2%9D%A4%EF%B8%8F-by%20Jonathan-red)](https://github.com/MrGuato)
[![pages-build-deployment](https://github.com/MrGuato/enshrouded-docker/actions/workflows/pages/pages-build-deployment/badge.svg)](https://mrguato.github.io/enshrouded-docker/)
[![Build & Push (GHCR)](https://github.com/MrGuato/enshrouded-docker/actions/workflows/docker-ghcr.yml/badge.svg)](https://github.com/MrGuato/enshrouded-docker/actions/workflows/docker-ghcr.yml)
[![GHCR](https://img.shields.io/badge/GHCR-container%20registry-blue)](https://github.com/mrguato/enshrouded-docker/pkgs/container/enshrouded-docker)
![Visitors](https://visitor-badge.laobi.icu/badge?page_id=mrguato.enshrouded-docker)

# Enshrouded Dedicated Server (Docker)

A simple, one-command way to host an Enshrouded dedicated server on any Linux machine.

Whenever the container starts, it checks SteamCMD and downloads the latest Enshrouded update automatically. You don't have to rebuild the image or manually patch the server every time the game updates, and your world saves stay safely stored in a folder on your host machine.

📖 **[Full Setup Guide & Docs](https://mrguato.github.io/enshrouded-docker/)**

---

## One-Command Linux Setup

If you have a fresh Linux machine (Ubuntu, Debian, Fedora, Arch, etc.), just run this in your terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/MrGuato/enshrouded-docker/main/setup.sh | bash
```

If you want to set your server name and password right away, you can pass them in the same command:

```bash
SERVER_NAME="Our Enshrouded World" SERVER_PASSWORD="myPassword123" SERVER_SLOTS=16 \
  curl -fsSL https://raw.githubusercontent.com/MrGuato/enshrouded-docker/main/setup.sh | bash
```

### What `setup.sh` does for you:
1. Installs `git`, `curl`, and **Docker + Docker Compose** if you don't already have them (and starts everything right away without making you log out and back in).
2. Sets up the server folder at `~/enshrouded-docker`.
3. Creates a `.env` file using your Linux user's permissions (`PUID`/`PGID`), so you won't run into `sudo` permission issues when backing up saves or editing configs.
4. Opens UDP port `15637` on your Linux firewall automatically if `ufw` or `firewalld` is enabled.
5. Pulls the image and starts the server in the background.

> **First run note:** The first time the server starts, SteamCMD will download about 6 GB of game files. You can watch the progress with `cd ~/enshrouded-docker && docker compose logs -f`. Once you see `[Session] 'HostOnline' (up)`, the server is ready to join!

---

## Manual Setup (If You Already Have Docker)

If you already use Docker Compose and just want to set it up yourself:

```bash
git clone https://github.com/MrGuato/enshrouded-docker.git
cd enshrouded-docker
cp .env.example .env
nano .env
docker compose up -d
```

Watch the logs while it downloads and boots up:

```bash
docker compose logs -f
```

---

## Changing Server Settings (`.env`)

You can change your server settings inside the `.env` file (or directly in `docker-compose.yaml`), then run `docker compose up -d` to apply them. On startup, the container updates `enshrouded_server.json` with your `.env` values while keeping any custom gameplay/difficulty tweaks you've made.

| Variable | Default | What it does |
|---|---|---|
| `SERVER_NAME` | `Enshrouded Docker Server` | The name that shows up in the in-game server browser |
| `SERVER_SLOTS` | `16` | Max players allowed at once (`1`–`16`) |
| `SERVER_PASSWORD` | *(empty)* | Password for everyone to join (leave blank for a public server) |
| `ADMIN_PASSWORD` | *(empty)* | Optional password for the `Admin` role (can kick/ban, build, and open chests) |
| `FRIEND_PASSWORD` | *(empty)* | Optional password for the `Friend` role (can build and open chests, no kick/ban) |
| `GUEST_PASSWORD` | *(empty)* | Optional password for the `Guest` role (can explore and fight, but can't edit bases or open chests) |
| `QUERY_PORT` | `15637` | The UDP port used to connect and query the server |
| `ENABLE_VOICE_CHAT` | `false` | Set to `true` to turn on in-game voice chat |
| `VOICE_CHAT_MODE` | `Proximity` | `Proximity` or `Global` |
| `ENABLE_TEXT_CHAT` | `false` | Set to `true` to turn on in-game text chat |
| `GAME_SETTINGS_PRESET` | `Default` | Difficulty preset: `Default`, `Relaxed`, `Hard`, `Survival`, or `Custom` |
| `UPDATE_ON_START` | `1` | Checks Steam for game updates on start (`0` to skip) |
| `SYNC_CONFIG_ON_START` | `1` | Syncs `.env` settings into `enshrouded_server.json` on start (`0` if you prefer editing the JSON file completely by hand) |
| `PUID` / `PGID` | `1000` / `1000` | Your Linux user and group ID so you own the save and config files on the host |

---

## Where Your Files & Saves Live

Everything important is saved in three folders right inside `~/enshrouded-docker/`:

```text
enshrouded-docker/
├── enshrouded-config/
│   ├── enshrouded_server.json   ← Server config file
│   ├── savegame/                ← Your world saves (back this folder up!)
│   └── logs/                    ← Server logs
├── enshrouded-server/           ← Game files downloaded by SteamCMD (~6 GB)
└── enshrouded-wine/             ← Wine files
```

### Backing up your world

```bash
cd ~/enshrouded-docker
tar -czf "enshrouded-backup-$(date +%Y%m%d-%H%M%S).tar.gz" -C enshrouded-config savegame enshrouded_server.json
```

---

## Ports & Port Forwarding

Enshrouded uses **UDP port `15637`** for both gameplay and the server browser.
- If you are hosting on a cloud VM (AWS, Oracle, Hetzner, DigitalOcean, etc.), make sure **UDP 15637** is open in your cloud firewall / security group.
- If you are hosting at home, forward **UDP 15637** on your router to your Linux machine's local IP address.

---

## Useful Commands

```bash
# Watch live server logs
docker compose logs -f

# Restart the server (also installs any new Enshrouded game updates)
docker compose restart

# Apply changes after editing .env
docker compose up -d

# Stop the server safely (waits for world saves to finish writing)
docker compose down

# Pull the latest version of this Docker image
docker compose pull && docker compose up -d
```

---

## Changelog

See [CHANGELOG.md](./CHANGELOG.md) for what changed in **v0.2**.