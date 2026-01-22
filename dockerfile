FROM rouhim/steamcmd-wine:latest

LABEL maintainer="MrGuato"
LABEL description="Enshrouded Dedicated Server (SteamCMD installed deterministically)"
LABEL version="1.0"

ENV STEAM_APP_ID=2278520

ENV SERVER_DIR="/home/steam/server"
ENV SERVER_CONFIG_DIR="/home/steam/config"

ENV SERVER_NAME="Enshrouded Docker Server"
ENV SERVER_SLOTS=16
ENV SERVER_PASSWORD=""
ENV GAME_PORT=15637
ENV QUERY_PORT=27015
ENV UPDATE_ON_START=1

ENV WINEDEBUG=-all
ENV DISPLAY=":99"

USER root

# --- Create steam user/group in a portable way ---
RUN set -eux; \
    if ! id -u steam >/dev/null 2>&1; then \
      if command -v groupadd >/dev/null 2>&1; then \
        groupadd -r steam 2>/dev/null || true; \
        useradd  -r -m -g steam -s /bin/bash steam; \
      elif command -v addgroup >/dev/null 2>&1; then \
        addgroup -S steam 2>/dev/null || true; \
        adduser  -S -G steam -h /home/steam -s /bin/sh steam; \
      else \
        echo "No user-management tools found"; exit 1; \
      fi; \
    fi

# --- Install SteamCMD deterministically to /opt/steamcmd ---
RUN set -eux; \
    mkdir -p /opt/steamcmd; \
    cd /opt/steamcmd; \
    # Ensure we have curl + ca certs + tar available (handles Debian/Ubuntu and Alpine)
    if command -v apt-get >/dev/null 2>&1; then \
      apt-get update; \
      apt-get install -y --no-install-recommends curl ca-certificates tar; \
      rm -rf /var/lib/apt/lists/*; \
    elif command -v apk >/dev/null 2>&1; then \
      apk add --no-cache curl ca-certificates tar; \
      update-ca-certificates; \
    fi; \
    curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz -o steamcmd_linux.tar.gz; \
    tar -xzf steamcmd_linux.tar.gz; \
    rm -f steamcmd_linux.tar.gz; \
    chmod +x /opt/steamcmd/steamcmd.sh; \
    ln -sf /opt/steamcmd/steamcmd.sh /usr/local/bin/steamcmd.sh

# --- Create dirs + perms ---
RUN set -eux; \
    mkdir -p "${SERVER_DIR}" "${SERVER_CONFIG_DIR}"; \
    chown -R "$(id -u steam)":"$(id -g steam)" /home/steam

# --- Copy entrypoint WITHOUT --chown for max compatibility ---
COPY entrypoint.sh /home/steam/entrypoint.sh
RUN set -eux; \
    chmod +x /home/steam/entrypoint.sh; \
    chown "$(id -u steam)":"$(id -g steam)" /home/steam/entrypoint.sh

USER steam
WORKDIR /home/steam

EXPOSE 15637/udp 27015/udp

HEALTHCHECK --interval=60s --timeout=10s --start-period=180s --retries=3 \
  CMD pgrep -f enshrouded_server.exe >/dev/null 2>&1 || exit 1

ENTRYPOINT ["/home/steam/entrypoint.sh"]
