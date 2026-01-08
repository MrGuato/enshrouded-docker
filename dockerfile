FROM ubuntu:22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    STEAMCMDDIR=/opt/steamcmd \
    EN_DIR=/home/steam/enshrouded \
    WINEPREFIX=/home/steam/.wine \
    WINEDEBUG=-all

# 32-bit architecture for wine + steamcmd, install Wine and other dependencies
RUN dpkg --add-architecture i386 && apt-get update && apt-get install -y \
    ca-certificates curl wget unzip tini gosu \
    wine64 wine32 \
    xvfb \
    lib32gcc-s1 lib32stdc++6 \
    libwine-gecko3.0 libwine-gl3.0 \
    && rm -rf /var/lib/apt/lists/*

# Install SteamCMD
RUN mkdir -p ${STEAMCMDDIR} && \
    curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
      | tar -xz -C ${STEAMCMDDIR}

# Create unprivileged user
RUN useradd -m -u 10000 -s /bin/bash steam && \
    mkdir -p ${EN_DIR} && chown -R steam:steam /home/steam ${STEAMCMDDIR}

# Copy entrypoint script and make it executable
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose necessary ports
EXPOSE 15637/udp 27015/udp

# Define entrypoint and command
ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["/entrypoint.sh"]
