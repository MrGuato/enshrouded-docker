# Security policy

## Reporting a problem

Please don't open a public issue for a security problem. Use GitHub's private reporting instead: **Security > Report a vulnerability** on this repo. I'll reply within a week and credit you in the release notes if you'd like.

Useful things to include: what you found, how to reproduce it, and which image tag or commit you tested.

## What's covered

- The container image `ghcr.io/mrguato/enshrouded-docker`
- The scripts in this repo: `enshrouded`, `setup.sh`, the entrypoints, `scripts/`
- The GitHub Actions workflows

The Enshrouded server itself is Keen Games' software, downloaded from Steam at runtime. Problems in the game go to [Keen Games](https://enshrouded.com/). Problems in Wine go to the Wine project.

## Supported versions

| Version  | Supported |
| -------- | --------- |
| 1.x      | Yes |
| 0.x      | No (upgrade with `git pull && ./enshrouded update`) |

## How the project keeps itself safe

- The server runs as an unprivileged user (UID 1000) inside the container. Root is only used at start to fix volume ownership, then dropped with `gosu`.
- No secrets live in the repo. `.env` is gitignored, and `./enshrouded setup` writes it with mode 600. `enshrouded_server.json` holds the server passwords, so the entrypoint keeps it at mode 600 and backups are written readable by their owner only.
- Nothing on GitHub can reach your host. There's no self-hosted runner or deploy hook; the host pulls a public image.
- Nothing is downloaded at server start except the game itself, from Steam.
- Every push and pull request runs hadolint, shellcheck, CodeQL, gitleaks (secret scanning) and Trivy (repo config and the built image). Findings go to the repo's code scanning page.
- The image is rebuilt every week so Ubuntu and Wine security fixes land without waiting for a release, and Dependabot opens weekly updates for the base image and GitHub Actions.
