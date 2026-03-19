#!/usr/bin/env bash
set -euo pipefail

# Install dependencies
if ! command -v git &>/dev/null || ! command -v docker &>/dev/null; then
  sudo apt-get update
  sudo apt-get install -y git
fi

# Install Docker
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$USER"
  echo ""
  echo "Docker installed. Log out and back in, then re-run this script."
  exit 0
fi

# Install compose plugin if missing
if ! docker compose version &>/dev/null 2>&1; then
  sudo apt-get update && sudo apt-get install -y docker-compose-plugin
fi

# Clone repo if not already present
if [[ ! -f "docker-compose.yml" ]]; then
  git clone https://github.com/MrGuato/enshrouded-docker .
fi

# Pull latest image and start
docker compose pull
docker compose up -d

echo ""
echo "Server starting (~6GB download on first run)."
echo "Follow logs: docker logs -f enshrouded-server"
echo "Ports: 15637/udp (game), 27015/udp (query)"