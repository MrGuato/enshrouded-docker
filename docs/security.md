---
title: Security
layout: default
nav_order: 6
---

# Security

A game server is a long-running process that listens on the internet, so the image tries to keep the blast radius small.

## What runs, and as whom

- The container starts as root only long enough to fix volume ownership, then drops to the `steam` user (UID 1000 by default) with `gosu`. Set `PUID`/`PGID` to match your host user.
- The game runs under Wine with a virtual display (Xvfb) that listens on no network socket.
- Nothing is downloaded at server start except the game itself, from Steam, through SteamCMD's anonymous login.

## Secrets

- `.env` is gitignored, and `./enshrouded setup` writes it with mode 600.
- `enshrouded_server.json` holds the server passwords. The entrypoint keeps it at mode 600.
- Backup tarballs contain that file, so `scripts/backup.sh` creates them readable by their owner only. Treat off-host copies the same way.

## Your host and GitHub

There is no self-hosted runner, deploy key or webhook. GitHub builds and publishes a public image; your host pulls it. Nothing on GitHub can reach your machine.

Watchtower needs the Docker socket to recreate the container. It only acts on containers with the `com.centurylinklabs.watchtower.enable=true` label. If you would rather not give any container the socket, remove the `watchtower` service and update with `./enshrouded update`.

## The build pipeline

Every push and pull request runs:

| Check | What it looks at |
| ----- | ---------------- |
| hadolint | The Dockerfile |
| shellcheck | Every shell script, including `enshrouded` |
| CodeQL | The GitHub Actions workflows (GitHub default setup) |
| gitleaks | Secrets anywhere in the git history |
| Trivy | Repo misconfigurations and vulnerabilities in the built image |

Findings go to the repo's code scanning page. Dependabot opens weekly updates for the base image and the actions, and the image is rebuilt every Monday for Ubuntu and Wine security fixes.

`.trivyignore` lists one accepted finding: the image starts as root on purpose (see above), so the "image user should not be root" check stays closed.

## Hardening your server

- Set a password. With roles, give most players `FRIEND_PASSWORD` or `GUEST_PASSWORD` and keep `ADMIN_PASSWORD` to yourself.
- Forward only UDP 15637.
- Pin `IMAGE_TAG` to a release if you want to review changes before they reach your host.
- Keep an off-host copy of your backups.

## Reporting a problem

Please use GitHub's private reporting (**Security > Report a vulnerability**) instead of a public issue. Details are in [SECURITY.md](https://github.com/MrGuato/enshrouded-docker/blob/main/SECURITY.md).
