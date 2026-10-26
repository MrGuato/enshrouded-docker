# Changelog

All notable changes to this project. Releases follow [semantic versioning](https://semver.org/); image tags drop the `v` (`v1.0.0` becomes `1.0.0` and `1.0`).

## [1.0.0] - 2026-10-25

The project now works the same way as my [Valheim server](https://github.com/MrGuato/valheim-game-server): one CLI, real backups, a documentation site and a scanned build pipeline.

### Added
- `./enshrouded` CLI: `setup` wizard, `start`, `stop`, `restart`, `down`, `status`, `logs`, `update`, `backup`, `restore`, `shell`, `build`. A `Makefile` wraps it.
- `scripts/backup.sh` and `scripts/restore.sh`: verified tarballs of the world saves and server config, with retention. Archives are readable by their owner only because the config holds the passwords.
- Settings are checked before the server starts: slots (1 to 16), ports, `GAME_SETTINGS_PRESET` and `VOICE_CHAT_MODE`. A warning is logged when no password is set.
- `STOP_TIMEOUT` (default 90 s): how long the server gets to exit after Ctrl+C before Wine is stopped.
- `IMAGE_REPOSITORY`, `IMAGE_TAG` and `CONTAINER_NAME` in `.env`, so a release can be pinned.
- Watchtower in the compose file: checks for a new image at 05:00 daily and only updates this container.
- Healthcheck script with a 15-minute start period for the first download, and log rotation.
- Documentation site on Just the Docs at <https://mrguato.github.io/enshrouded-docker/>: installation, configuration, updates, backups, security and troubleshooting.
- A logo.
- Lint (hadolint, shellcheck) and Security (gitleaks, Trivy config and image scans) workflows, next to the CodeQL default setup. Dependabot now actually watches the base image and the actions.
- `SECURITY.md`.

### Changed
- `setup.sh` is now a thin installer: it installs Docker if needed, clones the repo, runs `./enshrouded setup --yes` and starts the server. The whole script is read before anything runs, so `curl | bash` can't be cut short.
- The README's inline-settings example put the variables on the `curl` side of the pipe, where they never reached the script. It's now `curl ... | SERVER_NAME=... bash`.
- `GAME_SETTINGS_PRESET` now applies on every start, unless `enshrouded_server.json` is set to `Custom`, in which case it is never overwritten. Before, the preset in `.env` only counted the first time.
- `enshrouded_server.json` is kept at mode 600. A file that isn't valid JSON is kept as `.broken` instead of being overwritten silently.
- Switches accept `true`/`false` as well as `1`/`0`. Existing `.env` files keep working.
- The image applies Ubuntu's pending package updates at build time, drops the unused ipp-usb printer daemon that Wine pulls in (Trivy flagged 125 Go CVEs in it), and is rebuilt every Monday. Date tags are no longer published; use `latest`, a release tag or `sha-` tags.
- The entrypoint scripts moved to `/usr/local/bin`, and `dockerfile` is now `Dockerfile`.

### Removed
- The old single-page site (`docs/index.html`, `docs/guide.md`), replaced by the documentation site.

### Upgrading from 0.2
Your folders and `.env` carry over unchanged.
1. `tar -czf enshrouded-before-1.0.tar.gz enshrouded-config` (or copy the folder somewhere safe).
2. `git pull`
3. `./enshrouded update`

## [0.2] - 2026-10-17

This update focuses on making the server a true one-command install on Linux, fixing where world saves are stored, and replacing the old project pages with a proper setup guide.

### What's New
- **True one-shot Linux installer (`setup.sh`):**
  - You no longer have to log out, log back in, and run the script a second time after Docker installs.
  - Fixed a bug where cloning failed if you ran the script from a non-empty home folder (`~`). It now sets everything up cleanly in `~/enshrouded-docker`.
  - Automatically creates a `.env` file and opens UDP port `15637` on `ufw` or `firewalld` if active.
- **Fixed world save and log folder locations:**
  - Linked `savegame`, `logs`, and `enshrouded_server.json` between the server directory and `enshrouded-config/` so saves actually go into `enshrouded-config/savegame/` instead of getting buried in the server binaries folder (any existing saves are moved over automatically).
- **Easier configuration and role passwords:**
  - Changes in `.env` (like server name, player slots, voice/text chat, or passwords) now update `enshrouded_server.json` automatically on startup without wiping out custom difficulty settings.
  - Added support for Enshrouded's role passwords (`ADMIN_PASSWORD`, `FRIEND_PASSWORD`, `GUEST_PASSWORD`) as well as a simple single `SERVER_PASSWORD`.
- **Safer shutdowns and fewer permission headaches:**
  - Stopping the container now waits for Wine and Enshrouded to finish before exiting.
  - Added `PUID` and `PGID` support (defaulting to `1000:1000`) so your regular Linux user owns the config and save files on the host.
  - Added automatic retries if SteamCMD has a hiccup while downloading updates.
- **New Setup Guide:**
  - Replaced the old Notion-style showcase page in `docs/` with a step-by-step Linux setup and troubleshooting guide with copyable commands.

## [0.1] - 2026-01-03

- Initial public release of the Enshrouded Dedicated Server Docker image with SteamCMD auto-updates on startup and Wine64 runtime.

[1.0.0]: https://github.com/MrGuato/enshrouded-docker/compare/v0.2...v1.0.0
[0.2]: https://github.com/MrGuato/enshrouded-docker/releases/tag/v0.2
