---
title: Backups
layout: default
nav_order: 5
---

# Backups

Three layers, cheapest first.

## 1. Enshrouded's own rolling saves

The server keeps a few older copies of each world next to the current one in `enshrouded-config/savegame/`. They protect against a corrupted save, not against losing the disk.

## 2. Repo backup script

```bash
./enshrouded backup
```

Writes `./backups/enshrouded-YYYY-MM-DD-HHMM.tar.gz` containing `enshrouded-config/savegame/` and `enshrouded_server.json`, verifies the archive, and deletes archives older than 14 days. The archive holds your server passwords, so it is created readable by its owner only.

```bash
BACKUP_DIR=/srv/backups RETENTION_DAYS=60 ./enshrouded backup
```

Schedule it:

```cron
30 9 * * 0 cd /home/you/enshrouded-docker && ./enshrouded backup >> logs/backup.log 2>&1
```

If `./enshrouded-config` is root-owned (you run with `PUID=0`), run it with `sudo`.

The game files in `./enshrouded-server`, the Wine prefix and the image are reproducible and are intentionally left out.

## 3. Off-host copies

Everything above lives on the same disk as the server. Push the tarballs somewhere else after each backup:

```bash
rsync -av ./backups/ backup@nas:/srv/backups/enshrouded/
```

S3-compatible storage with the AWS CLI:

```bash
aws s3 sync ./backups/ s3://my-bucket/enshrouded/ --exclude "*" --include "enshrouded-*.tar.gz"
```

Restic, Borg or rclone all work the same way. Chain the command after `./enshrouded backup` in the cron entry.

## Restore

```bash
./enshrouded restore ./backups/enshrouded-2026-10-25-0930.tar.gz
```

The script asks for confirmation, stops the server, extracts the archive over `enshrouded-config/`, and starts the server again. Always restore into the same project directory the backup was taken from, and take a fresh backup before restoring so the current state is not lost.

## Moving a world from another host

Stop the server, copy the world files from the other host's `savegame` folder (on Windows: the server's `savegame` folder next to `enshrouded_server.exe`) into `enshrouded-config/savegame/`, then start the server. Fix the owner if you copied as root:

```bash
sudo chown -R 1000:1000 enshrouded-config
```
