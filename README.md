[![Made With Love](https://img.shields.io/badge/Made%20with%20%E2%9D%A4%EF%B8%8F-by%20Jonathan-red)](https://github.com/MrGuato)
[![pages-build-deployment](https://github.com/MrGuato/enshrouded-docker/actions/workflows/pages/pages-build-deployment/badge.svg)](https://github.com/MrGuato/enshrouded-docker/actions/workflows/pages/pages-build-deployment)
[![GHCR](https://img.shields.io/badge/GHCR-container%20registry-blue)](https://github.com/<your-username>/<repo>/pkgs/container)
![Visitors](https://visitor-badge.laobi.icu/badge?page_id=<your-username>.<repo>)



# Enshrouded Dedicated Server | Automated Docker Deployment

> **Always up-to-date Enshrouded Dedicated Server, packaged as an immutable Docker image with runtime auto-updates via SteamCMD.**

This project provides a **clean, reproducible, and automated** way to run an Enshrouded Dedicated Server using Docker. It is designed with **DevOps best practices** in mind: immutable infrastructure, automation-first workflows, and safe persistence of state.

---

## Why This Exists

Most existing Enshrouded server setups fall into one of these traps:

- ❌ Manual installs that drift over time
- ❌ Docker images that go stale when Steam updates the server
- ❌ Containers that require rebuilding just to get the latest game version
- ❌ Root containers, unclear persistence, or brittle startup logic

This project intentionally avoids those problems.

### Core Idea

> **The container is immutable. The game server is not.**

Instead of baking a specific server version into the image, this container ships **SteamCMD + Wine**, pulls the **latest Enshrouded Dedicated Server (Steam AppID `2278520`) on startup**, and starts the server only after update validation succeeds. This guarantees no broken `latest` tags, no manual updates, and no rebuilds just to patch the game.

---

## Architecture Overview

```
┌─────────────────────────┐
│ Docker Image (Immutable)│
│ • Ubuntu LTS            │
│ • SteamCMD              │
│ • Wine (Windows server) │
│ • Entrypoint logic      │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│ Runtime Update (Auto)   │
│ steamcmd                │
│ +app_update 2278520     │
│ validate                │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│ Persistent Data Volume  │
│ • World saves           │
│ • Logs                  │
│ • Server config         │
└─────────────────────────┘
```

---

## Why Docker Is the Right Tool Here

Docker provides reproducibility by ensuring every server instance starts from the **same known-good environment** - same OS, same dependencies, same startup logic - eliminating “it worked on my machine” issues. The container follows **immutable infrastructure** principles: no in-place OS changes, no snowflake servers, and no configuration drift. All state lives **only** in mounted volumes.

Docker also enables a **clean separation of concerns**: the image handles runtime dependencies and automation logic, volumes store world data and logs, and environment variables control behavior and tuning. This mirrors how real production workloads are deployed.

When Enshrouded releases an update, upgrades are safe and trivial: restart the container, SteamCMD pulls the latest build, and the server starts on the new version automatically - no rebuild pipelines, no guesswork.

---

## Automation & DevOps Practices Used

This repository includes a **Buildx-powered GitHub Actions CI/CD pipeline** that builds images on `main` branch pushes, scheduled daily runs, and manual dispatch. Images are published to **GitHub Container Registry (GHCR)** with intelligent tags including `latest`, `sha-<commit>`, `YYYYMMDD`, and optional SemVer tags like `v1.0.0`. This reflects modern container publishing workflows used in production platforms.

At runtime, the container entrypoint fully automates server updates, config generation (if missing), safe startup sequencing, non-root execution, and headless Wine execution via Xvfb. Once deployed, no manual intervention is required.

---

## Quick Start

Pull the image:

```bash
docker pull ghcr.io/<your-username>/<repo>:latest
```

Run with Docker Compose:

```yaml
services:
  enshrouded:
    image: ghcr.io/<your-username>/<repo>:latest
    restart: unless-stopped
    ports:
      - "15637:15637/udp"
      - "27015:27015/udp"
    environment:
      - UPDATE_ON_START=1
      - SERVER_NAME=My Enshrouded Server
      - SERVER_SLOTS=16
    volumes:
      - ./data:/home/steam/enshrouded
```

```bash
docker compose up -d
```

---

## Persistence Model

All persistent state is stored outside the container:

```
data/
 ├─ savegame/
 ├─ logs/
 ├─ enshrouded_server.json
```

You can rebuild images, switch tags, or move hosts without losing world data.

---

## Security Considerations

The container runs as a **non-root user**, uses a minimal base OS, avoids privileged mode, exposes only required UDP ports, and provides no inbound management interfaces. This aligns with basic container hardening guidance.

---

## Who This Is For

This project is for players who want a **set-and-forget** dedicated server, homelab users practicing real DevOps patterns, engineers who care about **clean automation**, and anyone tired of manually updating game servers.

---

## Philosophy

> Treat game servers like production services.

Even “fun” infrastructure should be automated, reproducible, observable, and easy to reason about. That mindset scales far beyond games.
