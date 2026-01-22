FROM rouhim/steamcmd-wine:latest

LABEL maintainer="MrGuato"
LABEL description="Enshrouded Dedicated Server with auto-updates via SteamCMD"
LABEL version="1.0"

ENV STEAM_APP_ID=2278520
ENV STEAM_APP_NAME="enshrouded"

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

# --- Create steam user/group in a portable way (Debian/Ubuntu OR Alpine) ---
RUN set -eux; \
    if ! id -u steam >/dev/null 2>&1; then \
      if command -v groupadd >/dev/null 2>&1; then \
        groupadd -r steam 2>/dev/null || true; \
        useradd  -r -m -g steam -s /bin/bash steam; \
      elif command -v addgroup >/dev/null 2>&1; then \
        addgroup -S steam 2>/dev/null || true; \
        adduser  -S -G steam -h /home/steam -s /bin/sh steam; \
      else \
        echo "No known user-management tools found (groupadd/useradd/addgroup/adduser)"; \
        exit 1; \
      fi; \
    fi; \
    mkdir -p "${SERVER_DIR}" "${SERVER_CONFIG_DIR}"; \
    chown -R "$(id -u steam)":"$(id -g steam)" /home/steam

# --- Copy entrypoint WITHOUT --chown (most compatible), then chown it ---
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
