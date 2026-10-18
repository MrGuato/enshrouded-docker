# Changelog

## v0.2 (2026-10-17)

This update focuses on making the server a true one-command install on Linux, fixing where world saves are stored, and replacing the old project pages with a proper setup guide.

### What's New
- **True one-shot Linux installer (`setup.sh`):**
  - You no longer have to log out, log back in, and run the script a second time after Docker installs.
  - Fixed a bug where cloning failed if you ran the script from a non-empty home folder (`~`). It now sets everything up cleanly in `~/enshrouded-docker`.
  - Automatically creates a `.env` file and opens UDP port `15637` on `ufw` or `firewalld` if active.
- **Fixed world save & log folder locations:**
  - Linked `savegame`, `logs`, and `enshrouded_server.json` between the server directory and `enshrouded-config/` so saves actually go into `enshrouded-config/savegame/` instead of getting buried in the server binaries folder (any existing saves are moved over automatically).
- **Easier configuration & role passwords:**
  - Changes in `.env` (like server name, player slots, voice/text chat, or passwords) now update `enshrouded_server.json` automatically on startup without wiping out custom difficulty settings.
  - Added support for Enshrouded's role passwords (`ADMIN_PASSWORD`, `FRIEND_PASSWORD`, `GUEST_PASSWORD`) as well as a simple single `SERVER_PASSWORD`.
- **Safer shutdowns & fewer permission headaches:**
  - Stopping the container now waits for Wine and Enshrouded to finish saving the world before exiting.
  - Added `PUID` and `PGID` support (defaulting to `1000:1000`) so your regular Linux user owns the config and save files on the host.
  - Added automatic retries if SteamCMD has a hiccup while downloading updates.
- **New Setup Guide:**
  - Replaced the old Notion-style showcase page in `docs/` with a step-by-step Linux setup and troubleshooting guide with copyable commands.

---

## v0.1 (2026-01-03)

- Initial public release of the Enshrouded Dedicated Server Docker image with SteamCMD auto-updates on startup and Wine64 runtime.
