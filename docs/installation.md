---
title: Installation
layout: default
nav_order: 2
---

# Installation

Two ways in: the one-line installer for a fresh host, or a manual setup if you already run Docker.

## Option A: one-line installer

On a fresh Ubuntu, Debian, Fedora or Arch host:

```bash
curl -fsSL https://raw.githubusercontent.com/MrGuato/enshrouded-docker/main/setup.sh | bash
```

The installer:

1. Installs git, curl, Docker Engine and the Compose plugin if they are missing. It uses `sudo docker` for the rest of the run, so you don't have to log out and back in first.
2. Clones this repo into `~/enshrouded-docker` (set `INSTALL_DIR` to change that), or updates it if it is already there.
3. Asks a few questions in your terminal and waits for the answers (see below), then writes `.env` with your user's UID and GID so you own the files on the host.
4. Opens UDP 15637 in `ufw` or `firewalld` when one of them is active.
5. Starts the server and prints the server name, password, and LAN and public addresses.

The questions, with what pressing Enter does:

| Question | Enter |
| -------- | ----- |
| Server name | `My Enshrouded Server` |
| Player slots, 1 to 16 | `16` |
| Password players join with | Generates a random 16-character password and shows it |
| Admin password for you (can kick and ban) | Skips it |
| Time zone | The host's time zone |

Then it shows the settings and asks `Write these settings? [Y/n]`. Answering `n` writes nothing.

Running the installer again on a host that already has a `.env` keeps it and skips the questions, so your settings are never overwritten. The one exception is an `.env` with no password (the 1.0.0 installer wrote those): then it offers to set one, and a server name if it is still the default.

If you set an admin password, the player password becomes the Friend role (build and open chests), because Enshrouded ignores the plain server password as soon as any role password exists. Everyone types the password they were given; the server picks the role from it.

### Without questions

Anything you put on the `bash` side of the pipe is used instead of asking (on the `curl` side it never reaches the script). `NONINTERACTIVE=1` asks nothing at all and generates a password if you didn't give one:

```bash
curl -fsSL https://raw.githubusercontent.com/MrGuato/enshrouded-docker/main/setup.sh | \
    NONINTERACTIVE=1 SERVER_NAME="Our Enshrouded World" SERVER_PASSWORD="change-me" SERVER_SLOTS=16 bash
```

Then skip to [Connect](#5-connect).

## Option B: manual setup

### 1. Install Docker

Follow Docker's guide for your distribution, or on Ubuntu:

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"
newgrp docker
docker run --rm hello-world
```

### 2. Clone the repo and run setup

```bash
git clone https://github.com/MrGuato/enshrouded-docker.git
cd enshrouded-docker
./enshrouded setup
```

The wizard asks the same questions as the installer: server name, player slots, the player password (Enter generates one), an optional admin password and your time zone. It writes `.env` (mode 600) and creates `enshrouded-config/`, `enshrouded-server/`, `enshrouded-wine/` and `backups/`. A Guest role password can go in `.env` afterwards, see [Configuration]({{ '/configuration.html' | relative_url }}).

To skip the wizard:

```bash
cp .env.example .env
nano .env
mkdir -p enshrouded-config enshrouded-server enshrouded-wine backups
```

### 3. Open the firewall

On the host:

```bash
sudo ufw allow 15637/udp
```

or with firewalld:

```bash
sudo firewall-cmd --permanent --add-port=15637/udp
sudo firewall-cmd --reload
```

On your router, forward UDP 15637 to the host. On a cloud VM, allow UDP 15637 in the security group.

### 4. Start the server

```bash
./enshrouded start
```

That pulls the image from GHCR, starts the container and tails the log. The first start downloads about 6 GB of game files through SteamCMD and creates the Wine prefix, which takes a few minutes. When you see this, the server is up:

```
[enshrouded] Starting: name='...' slots=16 port=15637/udp (password)
...
[Session] 'HostOnline' (up)
```

## 5. Connect

Find the server by name in the in-game server browser, or add it by address with `your.public.ip:15637`. Enter the password (or the role password you want to join with).

## Optional: build the image locally

```bash
./enshrouded build
IMAGE_REPOSITORY=enshrouded-docker IMAGE_TAG=dev ./enshrouded start
```

## Optional: scheduled backups

```bash
crontab -e
```

```cron
30 9 * * 0 cd /home/you/enshrouded-docker && ./enshrouded backup >> logs/backup.log 2>&1
```

See [Backups]({{ '/backups.html' | relative_url }}).

## Upgrading

The folders and `.env` from older versions keep working. From your existing checkout:

```bash
git pull
./enshrouded setup
./enshrouded update
```

`./enshrouded setup` leaves a `.env` alone unless it has no password; then it offers to set one. Old values like `UPDATE_ON_START=1` are still understood. Have a look at `.env.example` for newer options (`IMAGE_TAG`, `STOP_TIMEOUT`, `WINE_INIT_TIMEOUT`).
