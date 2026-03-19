# Guide — Enshrouded Dedicated Server (Docker)

> Deploy a fully automated, always-up-to-date Enshrouded Dedicated Server using Docker. No manual updates, no configuration drift, no root containers.

---

## How It Works

The container ships **Wine + SteamCMD** baked into the image. On every startup, it:

1. Starts a headless display (Xvfb) so Wine has somewhere to render
2. Runs SteamCMD to pull the latest Enshrouded Dedicated Server from Steam
3. Launches `enshrouded_server.exe` via Wine

The Docker image itself never changes between game updates — SteamCMD handles that at runtime. Your saves and config live in mounted volumes and survive any image rebuild or upgrade.

---

## Requirements

- Ubuntu 22.04+ VM (or any Linux host with Docker)
- ~10 GB free disk space (6 GB game + Wine prefix + saves)
- UDP ports 15637 and 27015 open on your firewall

---

## Option A — One-Line Setup (Fresh VM)

```bash
curl -fsSL https://raw.githubusercontent.com/MrGuato/enshrouded-docker/main/setup.sh | bash
```

This script:
- Installs Docker if not present
- Installs the Docker Compose plugin if missing
- Clones the repo if you're not already in it
- Runs `docker compose up -d --build`

> **Note:** If Docker was just installed, the script will exit and ask you to log out and back in (group membership change). Re-run the script after logging back in.

---

## Option B — Manual (Docker Already Installed)

```bash
git clone https://github.com/MrGuato/enshrouded-docker
cd enshrouded-docker
docker compose up -d
```

Watch startup progress:

```bash
docker compose logs -f
```

First run downloads ~6 GB from Steam. Subsequent starts are fast because the game files are cached in a volume.

---

## Configuration

Edit environment variables directly in `docker-compose.yml`, or pass them via a `.env` file in the same directory.

| Variable | Default | Description |
|---|---|---|
| `SERVER_NAME` | `Enshrouded Docker Server` | Name shown in the server browser |
| `SERVER_SLOTS` | `16` | Maximum players |
| `SERVER_PASSWORD` | *(empty)* | Leave empty for a public server |
| `GAME_PORT` | `15637` | UDP game port |
| `QUERY_PORT` | `27015` | UDP query port |
| `UPDATE_ON_START` | `1` | Set to `0` to skip Steam update on startup |
| `WINEPREFIX` | `/home/steam/.wine` | Wine prefix location (don't change unless you know why) |

### Example .env file

```env
SERVER_NAME=My Awesome Server
SERVER_SLOTS=8
SERVER_PASSWORD=secretpassword
UPDATE_ON_START=1
```

---

## Ports

| Port | Protocol | Purpose |
|---|---|---|
| `15637` | UDP | Game traffic (required) |
| `27015` | UDP | Server discovery / query (required) |

**Firewall (UFW):**
```bash
sudo ufw allow 15637/udp
sudo ufw allow 27015/udp
```

**iptables:**
```bash
sudo iptables -A INPUT -p udp --dport 15637 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 27015 -j ACCEPT
```

If you're on a home network, also forward both ports on your router to the VM's local IP.

---

## Persistence

All state lives outside the container in three directories created automatically on first run:

```
enshrouded-config/
 ├─ savegame/               ← world saves
 ├─ logs/                   ← server logs
 └─ enshrouded_server.json  ← auto-generated server config

enshrouded-server/          ← game binaries (SteamCMD target)
enshrouded-wine/            ← Wine prefix
```

You can safely:
- Rebuild or upgrade the Docker image
- Change the `SERVER_NAME`, slots, or password
- Move the entire directory to another host

Your world data will be intact as long as these directories are preserved.

---

## Updating the Server

Game updates happen automatically on container restart when `UPDATE_ON_START=1`. SteamCMD only downloads changed files, so updates are fast.

To also pull the latest Docker image:

```bash
docker compose pull
docker compose up -d
```

To restart without updating the game:

```bash
UPDATE_ON_START=0 docker compose up -d
```

---

## Common Operations

**Stop the server:**
```bash
docker compose down
```

**Restart:**
```bash
docker compose restart
```

**View live logs:**
```bash
docker compose logs -f
```

**Open a shell inside the container:**
```bash
docker exec -it enshrouded-server bash
```

**Back up your world:**
```bash
tar -czf enshrouded-backup-$(date +%Y%m%d).tar.gz enshrouded-config/savegame/
```

---

## Troubleshooting

### Server doesn't appear in the browser

1. Confirm UDP 15637 and 27015 are open: `sudo ufw status`
2. Check the container is running and ports are published: `docker ps`
3. If behind a router, verify port forwarding is pointing to this VM's IP
4. Wait ~60 seconds after startup — the healthcheck starts period is 3 minutes

### Container exits immediately after starting

Check logs:
```bash
docker compose logs --tail=50
```

Common causes:
- SteamCMD failed to reach Steam (transient — restart and try again)
- Game binary not found after SteamCMD run (check for download errors in the log)
- Volume permission issues (see below)

### Permission errors on the data directories

```bash
sudo chown -R $USER:$USER ./enshrouded-config ./enshrouded-server ./enshrouded-wine
```

### Wine or Xvfb errors in logs

These are usually harmless warnings from Wine initializing a new prefix. If the server still starts, ignore them. If it doesn't start, check that `enshrouded-wine/` is not corrupted — delete it and let the container re-initialize.

```bash
rm -rf ./enshrouded-wine
docker compose up -d
```

---

## Security Notes

- Runs as a non-root user inside the container (`steam`, uid 999)
- No privileged mode required
- Only UDP 15637 and 27015 are exposed — no management ports
- All persistent state is in explicit volume mounts — the container itself is stateless

---

## Recommended Practices

- Use `restart: unless-stopped` so the server comes back after a VM reboot
- Back up `enshrouded-config/savegame/` on a schedule (cron + tar works fine)
- Pin to a specific image tag (`sha-abc1234` or `YYYYMMDD`) if you want controlled upgrades instead of always-latest
- Keep `UPDATE_ON_START=1` — it protects you from running a mismatched server version after a game update

---

## Questions / Issues

Open an issue at [github.com/MrGuato/enshrouded-docker](https://github.com/MrGuato/enshrouded-docker)