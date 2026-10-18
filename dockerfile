FROM ubuntu:22.04

LABEL org.opencontainers.image.title="Enshrouded Dedicated Server" \
      org.opencontainers.image.description="Automated, rootless-runtime Enshrouded Dedicated Server with SteamCMD & Wine64" \
      org.opencontainers.image.source="https://github.com/MrGuato/enshrouded-docker" \
      org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    PUID=1000 \
    PGID=1000 \
    WINEARCH=win64 \
    WINEDEBUG=-all \
    WINEPREFIX=/home/steam/.wine \
    DISPLAY=:99 \
    STEAM_APP_ID=2278520 \
    SERVER_DIR=/home/steam/server \
    SERVER_CONFIG_DIR=/home/steam/config \
    SERVER_NAME="Enshrouded Docker Server" \
    SERVER_SLOTS=16 \
    SERVER_PASSWORD="" \
    ADMIN_PASSWORD="" \
    FRIEND_PASSWORD="" \
    GUEST_PASSWORD="" \
    SERVER_IP="0.0.0.0" \
    GAME_PORT=15637 \
    QUERY_PORT=15637 \
    ENABLE_VOICE_CHAT=false \
    ENABLE_TEXT_CHAT=false \
    VOICE_CHAT_MODE="Proximity" \
    GAME_SETTINGS_PRESET="Default" \
    UPDATE_ON_START=1 \
    SYNC_CONFIG_ON_START=1 \
    STEAMCMD_DIR=/opt/steamcmd \
    PATH="/opt/steamcmd:${PATH}"

USER root

RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      gnupg2 \
      jq \
      gosu \
      lib32gcc-s1 \
      locales \
      procps \
      software-properties-common \
      tzdata \
       unzip \
      wget \
      winbind \
      xvfb \
      xauth \
 && locale-gen en_US.UTF-8 \
 && mkdir -pm755 /etc/apt/keyrings \
 && wget -qO /etc/apt/keyrings/winehq-archive.key \
      https://dl.winehq.org/wine-builds/winehq.key \
 && wget -qNP /etc/apt/sources.list.d/ \
      https://dl.winehq.org/wine-builds/ubuntu/dists/jammy/winehq-jammy.sources \
 && apt-get update \
 && apt-get install -y --install-recommends \
      winehq-stable \
      wine-stable-amd64 \
      wine-stable-i386:i386 \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

RUN groupadd -g 1000 -o steam \
 && useradd -u 1000 -g steam -o -m -s /bin/bash steam

RUN mkdir -p /opt/steamcmd \
 && curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
      | tar -xzf - -C /opt/steamcmd \
 && chmod +x /opt/steamcmd/steamcmd.sh \
 && chown -R steam:steam /opt/steamcmd

RUN mkdir -p /home/steam/server /home/steam/config /home/steam/.wine \
 && chown -R steam:steam /home/steam

COPY docker-entrypoint.sh /docker-entrypoint.sh
COPY entrypoint.sh /home/steam/entrypoint.sh

RUN sed -i 's/\r$//' /docker-entrypoint.sh /home/steam/entrypoint.sh \
 && chmod +x /docker-entrypoint.sh /home/steam/entrypoint.sh \
 && chown steam:steam /home/steam/entrypoint.sh

# Stay as root initially — docker-entrypoint.sh aligns PUID/PGID & permissions then drops to steam via gosu
USER root
WORKDIR /home/steam

EXPOSE 15637/udp 27015/udp

STOPSIGNAL SIGTERM

HEALTHCHECK --interval=60s --timeout=10s --start-period=300s --retries=3 \
  CMD pgrep -f enshrouded_server.exe >/dev/null 2>&1 || exit 1

ENTRYPOINT ["/docker-entrypoint.sh"]