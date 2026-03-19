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

# SteamCMD lives here — add to PATH so steamcmd.sh resolves linux32/ correctly
ENV STEAMCMD_DIR=/opt/steamcmd
ENV PATH="/opt/steamcmd:${PATH}"

USER root

# System deps + WineHQ stable
RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      wget gnupg2 ca-certificates software-properties-common \
 && wget -O /etc/apt/keyrings/winehq-archive.key \
      https://dl.winehq.org/wine-builds/winehq.key \
 && wget -NP /etc/apt/sources.list.d/ \
      https://dl.winehq.org/wine-builds/ubuntu/dists/jammy/winehq-jammy.sources \
 && apt-get update \
 && apt-get install -y --install-recommends winehq-stable \
 && apt-get install -y --no-install-recommends \
      xvfb procps curl lib32gcc-s1 \
 && rm -rf /var/lib/apt/lists/*

# Create steam user
RUN groupadd -r steam && useradd -r -m -g steam -s /bin/bash steam

# Install SteamCMD directly into /opt/steamcmd — no symlinks
RUN mkdir -p /opt/steamcmd \
 && curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
      | tar -xzf - -C /opt/steamcmd \
 && chmod +x /opt/steamcmd/steamcmd.sh \
 && chown -R steam:steam /opt/steamcmd

# Dirs + permissions
RUN mkdir -p /home/steam/server /home/steam/config \
 && chown -R steam:steam /home/steam

COPY entrypoint.sh /home/steam/entrypoint.sh
RUN chmod +x /home/steam/entrypoint.sh \
 && chown steam:steam /home/steam/entrypoint.sh

USER steam
WORKDIR /home/steam

EXPOSE 15637/udp 27015/udp

HEALTHCHECK --interval=60s --timeout=10s --start-period=300s --retries=3 \
  CMD pgrep -f enshrouded_server.exe >/dev/null 2>&1 || exit 1

ENTRYPOINT ["/home/steam/entrypoint.sh"]