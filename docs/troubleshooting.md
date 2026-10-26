---
title: Troubleshooting
layout: default
nav_order: 10
---

# Troubleshooting

Start with these two:

```bash
./enshrouded status
./enshrouded logs 200
```

## The container exits right away with a settings error

```
[enshrouded] ERROR: SERVER_SLOTS must be a number from 1 to 16
[enshrouded] ERROR: GAME_SETTINGS_PRESET must be Default, Relaxed, Hard, Survival or Custom
```

Settings are checked before anything is downloaded. Fix `.env` and run `./enshrouded update`.

## Health stays `starting` or `unhealthy`

The healthcheck has a 15-minute start period to cover the first 6 GB download. If it never turns healthy, look in the log for SteamCMD errors (network, disk full) or a Wine error right after `Starting:`.

## SteamCMD fails to install

Symptom: `ERROR! Failed to install app '2278520'`.

- Outbound internet must work from the container: `docker run --rm curlimages/curl -sI https://steamcdn-a.akamaihd.net/`
- At least 12 GB free disk during the first download
- `enshrouded-server/` must be writable by `PUID:PGID` (see permissions below)

`Missing configuration` on the first attempt is a SteamCMD quirk, not a real failure. The entrypoint warms SteamCMD up and retries; the second attempt normally succeeds. Retry with `./enshrouded restart`, SteamCMD resumes partial downloads.

## Permission denied on saves or game files

The server runs as `PUID:PGID` (1000 by default). The container fixes ownership on start when it runs as root, which is the default. If you start it with `--user` or your host blocks `chown`, do it yourself:

```bash
sudo chown -R 1000:1000 enshrouded-config enshrouded-server enshrouded-wine
./enshrouded restart
```

## Server not visible in the browser

- Wait for `[Session] 'HostOnline' (up)` in the log. Until then the server isn't listening.
- UDP 15637 open on the host firewall (`sudo ufw status`) and in your cloud security group
- UDP 15637 forwarded on your router to the host's LAN address
- Search by the exact `SERVER_NAME`, or add the server by address with `your.public.ip:15637`

## Xvfb failed to start

```
[enshrouded] ERROR: Xvfb failed to start on :99
```

Usually a stale lock from a container that was killed. The entrypoint clears the lock on start when it runs as root; with `--user` it can't. Remove the container and start fresh:

```bash
./enshrouded down
./enshrouded start
```

## Stuck at "Creating the Wine prefix"

On 1.0.0, a new Wine prefix could offer to install Wine Mono and Gecko in a dialog on the invisible display and wait forever. 1.0.1 turns those off (`WINEDLLOVERRIDES=mscoree,mshtml=`, the server needs neither) and gives up waiting after `WINE_INIT_TIMEOUT` seconds. Update, and start with a fresh prefix:

```bash
./enshrouded down
sudo rm -rf enshrouded-wine
./enshrouded update
```

## Wine prefix initialization failed

Delete the prefix and let the next start create a new one. It holds no saves:

```bash
./enshrouded down
sudo rm -rf enshrouded-wine
./enshrouded start
```

## My difficulty changes keep getting reset

Set `GAME_SETTINGS_PRESET=Custom` in `.env`. Any other preset is written into the JSON on every start; `Custom` is never overwritten. Or set `SYNC_CONFIG_ON_START=false` to manage the whole file by hand.

## Players can't use the role they expect

Role passwords replace `SERVER_PASSWORD` as soon as any of them is set. Players get the role whose password they type. Check `enshrouded-config/enshrouded_server.json` under `userGroups` to see what the server is using.

## The host is ARM (Raspberry Pi, Ampere)

Not supported. Enshrouded only ships a Windows x86_64 server, and this image runs it with Wine on x86_64.
