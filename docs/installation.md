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

To set the server name and password in the same step, put them on the `bash` side of the pipe (on the `curl` side they never reach the script):

```bash
curl -fsSL https://raw.githubusercontent.com/MrGuato/enshrouded-docker/main/setup.sh | \
    SERVER_NAME="Our Enshrouded World" SERVER_PASSWORD="change-me" SERVER_SLOTS=16 bash
```

The installer:

1. Installs git, curl, Docker Engine and the Compose plugin if they are missing. It uses `sudo docker` for the rest of the run, so you don't have to log out and back in first.
2. Clones this repo into `~/enshrouded-docker` (set `INSTALL_DIR` to change that), or updates it if it is already there.
3. Runs `./enshrouded setup --yes`, which writes `.env` with your user's UID and GID so you own the files on the host.
4. Opens UDP 15637 in `ufw` or `firewalld` when one of them is active.
5. Starts the server and prints the LAN and public addresses.

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

The wizard asks for the server name, player slots, a password and your time zone. It writes `.env` (mode 600) and creates `enshrouded-config/`, `enshrouded-server/`, `enshrouded-wine/` and `backups/`. Role passwords (Admin, Friend, Guest) go in `.env` afterwards, see [Configuration]({{ '/configuration.html' | relative_url }}).

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

## Upgrading from 0.x

The folders and `.env` from 0.x keep working. From your existing checkout:

```bash
git pull
./enshrouded update
```

Old values like `UPDATE_ON_START=1` are still understood. Have a look at `.env.example` for the new options (`IMAGE_TAG`, `STOP_TIMEOUT`).
