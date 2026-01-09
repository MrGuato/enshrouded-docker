FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    STEAMCMDDIR=/opt/steamcmd \
    EN_DIR=/home/steam/enshrouded \
    WINEPREFIX=/home/steam/.wine \
    WINEDEBUG=-all

# Base deps + WineHQ repo + modern Wine
RUN dpkg --add-architecture i386 && \
    apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget unzip tini gosu gnupg2 software-properties-common \
      xvfb winbind cabextract \
    && mkdir -p /etc/apt/keyrings \
    && wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key \
    && wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/jammy/winehq-jammy.sources \
    && apt-get update \
    && apt-get install -y --install-recommends winehq-stable \
    && rm -rf /var/lib/apt/lists/*

# Install SteamCMD
RUN mkdir -p ${STEAMCMDDIR} && \
    curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
      | tar -xz -C ${STEAMCMDDIR}

# Create unprivileged user
RUN useradd -m -u 10000 -s /bin/bash steam && \
    mkdir -p ${EN_DIR} && chown -R steam:steam /home/steam ${STEAMCMDDIR} ${EN_DIR}

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 15637/udp 27015/udp

ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["/entrypoint.sh"]
