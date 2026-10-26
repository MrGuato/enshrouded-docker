# Enshrouded Dedicated Server (Windows build under Wine) by MrGuato
# The image is immutable: it ships SteamCMD, Wine and Xvfb only. The game files are downloaded
# and validated on every container start (UPDATE_ON_START=true), so the image never goes stale
# between Enshrouded patches. Saves and config live in /home/steam/config.
FROM ubuntu:26.04

LABEL org.opencontainers.image.title="Enshrouded Dedicated Server" \
      org.opencontainers.image.description="Enshrouded Dedicated Server (SteamCMD + Wine) by MrGuato" \
      org.opencontainers.image.source="https://github.com/MrGuato/enshrouded-docker" \
      org.opencontainers.image.authors="MrGuato" \
      org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    STEAMCMD_DIR=/opt/steamcmd \
    SERVER_DIR=/home/steam/server \
    CONFIG_DIR=/home/steam/config \
    STEAM_APP_ID=2278520 \
    WINEARCH=win64 \
    WINEDEBUG=-all \
    WINEPREFIX=/home/steam/.wine \
    DISPLAY=:99

RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get upgrade -y --no-install-recommends \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg jq gosu locales procps tzdata \
      lib32gcc-s1 lib32stdc++6 libc6:i386 winbind xvfb xauth \
 && sed -i 's/^# \(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen \
 && locale-gen \
 # WineHQ repo for this Ubuntu release. apt 3 only reads binary keys from a .key file, so dearmor it.
 && . /etc/os-release \
 && install -d -m 0755 /etc/apt/keyrings \
 && curl -fsSL https://dl.winehq.org/wine-builds/winehq.key | gpg --dearmor -o /etc/apt/keyrings/winehq-archive.key \
 && curl -fsSL -o "/etc/apt/sources.list.d/winehq-${VERSION_CODENAME}.sources" \
      "https://dl.winehq.org/wine-builds/ubuntu/dists/${VERSION_CODENAME}/winehq-${VERSION_CODENAME}.sources" \
 && apt-get update \
 && apt-get install -y --install-recommends winehq-stable \
 # Wine's recommends can pull in ipp-usb, a USB printer daemon (Go) a headless server never uses;
 # Trivy flagged 125 Go CVEs in it
 && if dpkg -s ipp-usb >/dev/null 2>&1; then apt-get purge -y ipp-usb; fi \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
 # the base image ships Canonical's pebble service manager; unused here and a CVE magnet
 && rm -f /usr/bin/pebble

# Ubuntu 24.04+ images ship a default "ubuntu" user on UID/GID 1000; make room for ours
RUN (id ubuntu >/dev/null 2>&1 && userdel -r ubuntu || true) \
 && groupadd -g 1000 steam \
 && useradd -u 1000 -g 1000 -m -s /bin/bash steam \
 && mkdir -p "$STEAMCMD_DIR" "$SERVER_DIR" "$CONFIG_DIR" "$WINEPREFIX" \
 && curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
      | tar -xz -C "$STEAMCMD_DIR" \
 && chown -R steam:steam "$STEAMCMD_DIR" /home/steam

COPY docker-entrypoint.sh entrypoint.sh healthcheck.sh /usr/local/bin/
RUN sed -i 's/\r$//' /usr/local/bin/docker-entrypoint.sh /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh \
 && chmod 755 /usr/local/bin/docker-entrypoint.sh /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh

# 15637 is the query port Enshrouded uses for players and the server browser
EXPOSE 15637/udp 27015/udp

WORKDIR /home/steam

STOPSIGNAL SIGTERM

HEALTHCHECK --interval=30s --timeout=10s --start-period=15m --retries=5 \
  CMD ["/usr/local/bin/healthcheck.sh"]

# Starts as root to fix volume ownership, then drops to the steam user (see docker-entrypoint.sh)
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
