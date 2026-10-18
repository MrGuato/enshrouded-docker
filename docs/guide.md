# Enshrouded Dedicated Server — Linux Setup & Operations Guide

> Deploy a fully automated, always-up-to-date Enshrouded Dedicated Server on any Linux machine using Docker. No manual Steam updates, no root runtime, no permission headaches.

---

## 1. One-Shot Linux Install (Recommended)

On any fresh Ubuntu, Debian, Fedora, or Arch Linux machine, run:

```bash
curl -fsSL https://raw.githubusercontent.com/MrGuato/enshrouded-docker/main/setup.sh | bash
```

Want to set your server name, password, and player slots immediately in the same command?

```bash
SERVER_NAME="Flameborn Server" SERVER_PASSWORD="mySecretPassword" SERVER_SLOTS=16 \
  curl -fsSL https://raw.githubusercontent.com/MrGuato/enshrouded-docker/main/setup.sh | bash
```

### What `setup.sh` handles automatically:
1. Installs `git`, `curl`, and **Docker Engine + Docker Compose** if missing — **without** requiring you to log out and re-run the script.
2. Clones/updates the setup into `~/enshrouded-docker`.
3. Generates `.env` matched to your Linux user's UID/GID (`PUID`/`PGID`) so you never get permission errors when editing configs or backing up saves.
4. Opens UDP port `15637/udp` (and `27015/udp`) automatically if `ufw` or `firewalld` is active.
5. Pulls `ghcr.io/mrguato/enshrouded-docker:latest` and starts the server in the background.

---

## 2. Manual Setup (Docker Compose)

If you already have Docker and Docker Compose installed:

```bash
git clone https://github.com/MrGuato/enshrouded-docker.git
cd enshrouded-docker
cp .env.example .env
nano .env
docker compose up -d
```

Watch the first-run download (~6 GB from SteamCMD):

```bash
docker compose logs -f
```

When you see `[Session] 'HostOnline' (up)` in the logs, your server is live and ready for players.

---

## 3. Configuration (`.env` / Environment Variables)

Edit `.env` in your installation directory and run `docker compose up -d` to apply changes. When `SYNC_CONFIG_ON_START=1` (default), environment variables are synced into `enshrouded_server.json` on startup via `jq` without overwriting custom gameplay settings.

| Variable | Default | Description |
|---|---|---|
| `SERVER_NAME` | `Enshrouded Docker Server` | Name shown in the server browser |
| `SERVER_SLOTS` | `16` | Maximum players (`1`–`16`) |
| `SERVER_PASSWORD` | *(empty)* | Single password for all players (leave empty for public server) |
| `ADMIN_PASSWORD` | *(empty)* | Password for the `Admin` user group (kick/ban + base/chest access) |
| `FRIEND_PASSWORD` | *(empty)* | Password for the `Friend` user group (base/chest access, no kick/ban) |
| `GUEST_PASSWORD` | *(empty)* | Password for the `Guest` user group (explore only, no base/chest edits) |
| `QUERY_PORT` | `15637` | Primary UDP port for both game traffic and server discovery |
| `ENABLE_VOICE_CHAT` | `false` | Enable in-game voice chat (`true` / `false`) |
| `VOICE_CHAT_MODE` | `Proximity` | `Proximity` or `Global` |
| `ENABLE_TEXT_CHAT` | `false` | Enable in-game text chat (`true` / `false`) |
| `GAME_SETTINGS_PRESET` | `Default` | `Default`, `Relaxed`, `Hard`, `Survival`, or `Custom` |
| `UPDATE_ON_START` | `1` | Run SteamCMD update check on container start (`0` to skip) |
| `SYNC_CONFIG_ON_START` | `1` | Sync env vars into `enshrouded_server.json` on start (`0` to disable) |
| `PUID` / `PGID` | `1000` / `1000` | Host Linux user UID/GID for volume file ownership |

---

## 4. Ports & Firewall

Enshrouded uses **UDP `15637`** for both gameplay traffic and server browser queries.

**UFW (Ubuntu / Debian):**
```bash
sudo ufw allow 15637/udp
sudo ufw allow 27015/udp
```

**firewalld (Fedora / RHEL / Rocky):**
```bash
sudo firewall-cmd --permanent --add-port=15637/udp
sudo firewall-cmd --permanent --add-port=27015/udp
sudo firewall-cmd --reload
```

If hosting behind a home router, forward **UDP 15637** to your Linux machine's local LAN IP.

---

## 5. Persistence & Backups

All persistent data lives on your host inside `~/enshrouded-docker/`:

```text
enshrouded-docker/
├── enshrouded-config/
│   ├── enshrouded_server.json  ← Server configuration
│   ├── savegame/               ← World saves (back this up!)
│   └── logs/                   ← Server logs
├── enshrouded-server/          ← Cached SteamCMD game binaries (~6 GB)
└── enshrouded-wine/            ← Cached Wine64 prefix
```

### Back up your world
```bash
cd ~/enshrouded-docker
tar -czf "enshrouded-backup-$(date +%Y%m%d-%H%M%S).tar.gz" -C enshrouded-config savegame enshrouded_server.json
```

---

## 6. Common Operations

**View live logs:**
```bash
docker compose logs -f
```

**Restart & install latest Enshrouded patch:**
```bash
docker compose restart
```

**Apply `.env` configuration changes:**
```bash
docker compose up -d
```

**Update the Docker container image:**
```bash
docker compose pull && docker compose up -d
```

**Stop the server gracefully (flushes world saves):**
```bash
docker compose down
```

---

## 7. Troubleshooting

### Server doesn't appear in the browser
1. Wait for the initial ~6 GB SteamCMD download to finish (`docker compose logs -f` until `[Session] 'HostOnline' (up)`).
2. Confirm UDP port `15637` is open on your host firewall (`sudo ufw status`) and cloud security group.
3. Verify router port forwarding for UDP `15637` if hosting on a home network.

### Editing `enshrouded_server.json` manually
Always stop the server (`docker compose down`) before editing `./enshrouded-config/enshrouded_server.json` directly, as Enshrouded writes to this file during shutdown. If you manage `enshrouded_server.json` completely by hand, set `SYNC_CONFIG_ON_START=0` in `.env`.