#!/usr/bin/env bash
# One-shot setup for fresh Ubuntu VM
# Usage: bash setup.sh

set -euo pipefail

# Install Docker if missing
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$USER"
  echo "Docker installed. You may need to log out/in for group changes."
  echo "Run this script again after re-login, or prefix docker commands with sudo."
fi

# Verify compose plugin
if ! docker compose version &>/dev/null; then
  sudo apt-get update && sudo apt-get install -y docker-compose-plugin
fi

# Build and start
docker compose up -d --build
echo ""
echo "Server starting. Follow logs with: docker logs -f enshrouded-server"
echo "Ports: 15637/udp (game), 27015/udp (query)"