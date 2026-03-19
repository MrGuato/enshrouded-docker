FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
ENV WINEARCH=win64
ENV WINEDEBUG=-all
ENV DISPLAY=:99
ENV STEAM_APP_ID=2278520
ENV SERVER_DIR=/home/steam/server
ENV SERVER_CONFIG_DIR=/home/steam/config
ENV SERVER_NAME="Enshrouded Docker Server"
ENV SERVER_SLOTS=16
ENV SERVER_PASSWORD=""
ENV GAME_PORT=15637
ENV QUERY_PORT=27015
ENV UPDATE_ON_START=1
ENV STEAMCMD_DIR=/opt/steamcmd
ENV PATH="/opt/steamcmd:${PATH}"

USER root

RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      wget gnupg2 ca-certificates software-properties-common \
 && wget -O /etc/apt/keyrings/winehq-archive.key \
      https://dl.winehq.org/wine-builds/winehq.key \
 && wget -NP /etc/apt/sources.list.d/ \
      https://dl.winehq.org/wine-builds/ubuntu/dists/jammy/winehq-jammy.sources \
 && apt-get update \
 && apt-get install -y --install-recommends \
      winehq-stable \
      wine-stable-amd64 \
      wine-stable-i386:i386 \
 && apt-get install -y --no-install-recommends \
      xvfb procps curl lib32gcc-s1 gosu \
 && rm -rf /var/lib/apt/lists/*

RUN groupadd -r steam && useradd -r -m -g steam -s /bin/bash steam

RUN mkdir -p /opt/steamcmd \
 && curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
      | tar -xzf - -C /opt/steamcmd \
 && chmod +x /opt/steamcmd/steamcmd.sh \
 && chown -R steam:steam /opt/steamcmd

RUN mkdir -p /home/steam/server /home/steam/config \
 && chown -R steam:steam /home/steam

COPY docker-entrypoint.sh /docker-entrypoint.sh
COPY entrypoint.sh /home/steam/entrypoint.sh
RUN chmod +x /docker-entrypoint.sh /home/steam/entrypoint.sh \
 && chown steam:steam /home/steam/entrypoint.sh

# Stay as root — docker-entrypoint.sh fixes perms then drops to steam via gosu
USER root
WORKDIR /home/steam

EXPOSE 15637/udp 27015/udp

HEALTHCHECK --interval=60s --timeout=10s --start-period=300s --retries=3 \
  CMD pgrep -f enshrouded_server.exe >/dev/null 2>&1 || exit 1

ENTRYPOINT ["/docker-entrypoint.sh"]