---
title: Home
layout: default
nav_order: 1
---

<p align="center"><img src="{{ '/assets/logo.svg' | relative_url }}" width="120" alt="Enshrouded Dedicated Server logo"></p>

# Enshrouded Dedicated Server
{: .text-center }

A self-hosted Enshrouded dedicated server for Linux that keeps itself patched and your world safe.
{: .fs-6 .fw-300 .text-center }

[Get started]({{ '/installation.html' | relative_url }}){: .btn .btn-primary .mr-2 }
[View on GitHub](https://github.com/MrGuato/enshrouded-docker){: .btn .mr-2 }
[Releases](https://github.com/MrGuato/enshrouded-docker/releases){: .btn }
{: .text-center }

---

```bash
git clone https://github.com/MrGuato/enshrouded-docker.git
cd enshrouded-docker
./enshrouded setup
./enshrouded start
```

When the log says `[Session] 'HostOnline' (up)`, players find the server in the in-game browser or join with `your.public.ip:15637`.

On a fresh host without Docker, one line does all of it. It asks for a server name and password before anything starts:

```bash
curl -fsSL https://raw.githubusercontent.com/MrGuato/enshrouded-docker/main/setup.sh | bash
```

## Why this one

Enshrouded only ships a Windows dedicated server, so on Linux it has to run under Wine. That part is fiddly: SteamCMD has to be told to fetch the Windows build, Wine needs a prefix and a virtual display, and saves end up buried in the game files if you are not careful. This image handles all of that so you don't have to.

**Your world comes first.** Saves and config live in `./enshrouded-config`, never in the game files. `./enshrouded backup` writes verified tarballs with retention, and `./enshrouded restore` puts one back. Stops send the server Ctrl+C and give it time to exit before anything gets killed.

**Set it up once.** One CLI covers setup, status, logs, updates, backups and restores. The image ships SteamCMD and Wine only and patches the game on every start, so a restart is a game update. Watchtower pulls new images once a night.

**Safe by default.** The server runs as an unprivileged user. GitHub has no way into your host. The image is built in public and scanned on every change (hadolint, shellcheck, CodeQL, gitleaks, Trivy). See [Security]({{ '/security.html' | relative_url }}).

## What you get

- `./enshrouded` CLI for setup, lifecycle, status, updates, backups and restores (`make` works too)
- A one-line installer for fresh hosts that sets up Docker, the firewall and the server
- SteamCMD validates and updates the game files on every container start
- Settings from `.env` written into `enshrouded_server.json` on start, without touching your custom difficulty settings
- Role passwords for Admin, Friend and Guest, or one password for everyone
- Runs as `PUID`/`PGID` 1000 by default. Root is optional
- Clean shutdown with a timeout (`STOP_TIMEOUT`)
- Settings are checked before the server starts (slots, ports, preset, voice chat mode)
- Healthcheck, log rotation and nightly Watchtower updates
- Versioned releases you can pin (`IMAGE_TAG=1.0.0`)

## Pages

| Page | What's in it |
| ---- | ------------ |
| [Installation]({{ '/installation.html' | relative_url }}) | From a fresh Linux host to your first login |
| [Configuration]({{ '/configuration.html' | relative_url }}) | Every variable, passwords and roles, volumes |
| [Updates]({{ '/updates.html' | relative_url }}) | Game patches, image updates, pinning a release |
| [Backups]({{ '/backups.html' | relative_url }}) | Local, scheduled and off-host backups, restoring |
| [Security]({{ '/security.html' | relative_url }}) | What the image does to protect you, and how to report a problem |
| [Troubleshooting]({{ '/troubleshooting.html' | relative_url }}) | Common errors and fixes |

## Requirements

| Component      | Minimum |
| -------------- | ------- |
| OS             | Ubuntu 22.04+, Debian 12+, Fedora or Arch (any x86_64 Linux with Docker) |
| Docker         | 24.x or newer |
| Docker Compose | v2 (`docker compose`) |
| CPU            | 4 x86_64 cores. ARM hosts can't run it, the server needs Wine on x86_64 |
| RAM            | 8 GB, 16 GB for a full 16-player server |
| Disk           | 12 GB free (about 6 GB of game files plus the Wine prefix) |
| Network        | UDP 15637 forwarded to the host |

## Source

[github.com/MrGuato/enshrouded-docker](https://github.com/MrGuato/enshrouded-docker), MIT licensed. Enshrouded is a trademark of Keen Games GmbH. This project isn't affiliated with Keen Games and doesn't redistribute game files.
