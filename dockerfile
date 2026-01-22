# This image is battle-tested for Wine game servers
FROM cm2network/steamcmd:wine

LABEL maintainer="MrGuato"
LABEL description="Enshrouded Dedicated Server with auto-updates"

# Environment variables with sensible defaults
ENV STEAMAPPID=2278520 \
    STEAMAPP=enshrouded \
    EN_DIR=/home/steam/enshrouded-dedicated \
    UPDATE_ON_START=1 \
    WINEDEBUG=-all \
    DISPLAY=:1.0

# Server configuration defaults
ENV SERVER_NAME="Enshrouded Docker Server" \
    SERVER_SLOTS=16 \
    SERVER_PASSWORD="" \
    GAME_PORT=15637 \
    QUERY_PORT=27015

# Create game directory with proper permissions
USER root
RUN mkdir -p ${EN_DIR} && \
    chown -R steam:steam ${EN_DIR}

# Copy entrypoint script
COPY --chown=steam:steam entrypoint.sh /home/steam/entrypoint.sh
RUN chmod +x /home/steam/entrypoint.sh

# Switch back to steam user for security
USER steam
WORKDIR /home/steam

# Expose game ports
EXPOSE 15637/udp 27015/udp

# Health check to ensure server is running
HEALTHCHECK --interval=60s --timeout=10s --start-period=120s --retries=3 \
    CMD pgrep -f enshrouded_server.exe || exit 1

ENTRYPOINT ["/home/steam/entrypoint.sh"]
