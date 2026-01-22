FROM rouhim/steamcmd-wine:latest

LABEL maintainer="MrGuato"
LABEL description="Enshrouded Dedicated Server with auto-updates via SteamCMD"
LABEL version="1.0"

# ============================================================================
# Environment Configuration
# ============================================================================

# Steam App configuration
ENV STEAM_APP_ID=2278520
ENV STEAM_APP_NAME="enshrouded"

# Server paths
ENV SERVER_DIR="/home/steam/server"
ENV SERVER_CONFIG_DIR="/home/steam/config"

# Server configuration defaults (user-customizable)
ENV SERVER_NAME="Enshrouded Docker Server"
ENV SERVER_SLOTS=16
ENV SERVER_PASSWORD=""
ENV GAME_PORT=15637
ENV QUERY_PORT=27015
ENV UPDATE_ON_START=1

# Wine optimization
ENV WINEDEBUG=-all

# ============================================================================
# Setup
# ============================================================================

# Switch to root for installation
USER root

# Ensure steam user exists (may already exist in base image)
RUN id -u steam &>/dev/null || useradd -m -u 1000 -s /bin/bash steam

# Create directories and set permissions
RUN mkdir -p ${SERVER_DIR} ${SERVER_CONFIG_DIR} && \
    chown -R steam:steam /home/steam

# Copy entrypoint script
COPY --chown=steam:steam entrypoint.sh /home/steam/entrypoint.sh
RUN chmod +x /home/steam/entrypoint.sh

# Switch back to steam user for security
USER steam
WORKDIR /home/steam

# ============================================================================
# Network & Health
# ============================================================================

# Expose game ports
EXPOSE 15637/udp 27015/udp

# Health check to verify server is running
HEALTHCHECK --interval=60s --timeout=10s --start-period=180s --retries=3 \
    CMD pgrep -f enshrouded_server.exe || exit 1

# ============================================================================
# Entrypoint
# ============================================================================

ENTRYPOINT ["/home/steam/entrypoint.sh"]
