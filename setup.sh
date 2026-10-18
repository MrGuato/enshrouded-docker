#!/usr/bin/env bash
# =============================================================================
# Enshrouded Dedicated Server — One-Shot Linux Installer
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/MrGuato/enshrouded-docker/main/setup.sh | bash
#
# Optional inline overrides:
#   SERVER_NAME="My Server" SERVER_PASSWORD="secret" curl -fsSL .../setup.sh | bash
# =============================================================================
set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

log()  { echo -e "${GREEN}[✔]${NC} $*"; }
info() { echo -e "${BLUE}[i]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✘]${NC} $*" >&2; }

REPO_URL="https://github.com/MrGuato/enshrouded-docker.git"
INSTALL_DIR="${INSTALL_DIR:-$HOME/enshrouded-docker}"

SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    err "This script requires root privileges or 'sudo' to install packages."
    exit 1
  fi
fi

echo -e "${CYAN}${BOLD}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   Enshrouded Dedicated Server — One-Shot Linux Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${NC}"

# -----------------------------------------------------------------------------
# 1. Pre-flight system checks (Disk & RAM)
# -----------------------------------------------------------------------------
check_system_resources() {
  local free_gb
  free_gb=$(df -BG "$HOME" 2>/dev/null | awk 'NR==2 {gsub("G","",$4); print $4}' || echo "20")
  if [[ "${free_gb}" =~ ^[0-9]+$ ]] && [[ "${free_gb}" -lt 10 ]]; then
    warn "Low disk space detected (~${free_gb} GB free). At least 12 GB is recommended for SteamCMD + Wine."
  fi

  if [[ -r /proc/meminfo ]]; then
    local mem_mb
    mem_mb=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo || echo "8192")
    if [[ "${mem_mb}" =~ ^[0-9]+$ ]] && [[ "${mem_mb}" -lt 6000 ]]; then
      warn "System RAM is ${mem_mb} MB (< 6 GB). Enshrouded Dedicated Server recommends 8+ GB RAM (or a swapfile)."
    fi
  fi
}

# -----------------------------------------------------------------------------
# 2. Install base tools (git, curl, ca-certificates)
# -----------------------------------------------------------------------------
install_base_deps() {
  if ! command -v git >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
    info "Installing git and curl..."
    if command -v apt-get >/dev/null 2>&1; then
      $SUDO apt-get update -qq
      $SUDO apt-get install -y -qq git curl ca-certificates
    elif command -v dnf >/dev/null 2>&1; then
      $SUDO dnf install -y -q git curl ca-certificates
    elif command -v yum >/dev/null 2>&1; then
      $SUDO yum install -y -q git curl ca-certificates
    elif command -v pacman >/dev/null 2>&1; then
      $SUDO pacman -Sy --noconfirm git curl ca-certificates
    else
      err "Could not detect package manager to install git/curl. Please install them manually."
      exit 1
    fi
  fi
  log "Base dependencies ready (git, curl)"
}

# -----------------------------------------------------------------------------
# 3. Install Docker & Docker Compose plugin (without requiring logout!)
# -----------------------------------------------------------------------------
install_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    info "Docker not found — installing Docker Engine via get.docker.com..."
    curl -fsSL https://get.docker.com | $SUDO sh
    if command -v systemctl >/dev/null 2>&1; then
      $SUDO systemctl enable --now docker >/dev/null 2>&1 || true
    fi
    if [[ "$(id -u)" -ne 0 ]]; then
      $SUDO usermod -aG docker "${USER:-$(id -un)}" || true
    fi
    log "Docker Engine installed"
  else
    log "Docker Engine already installed"
    if command -v systemctl >/dev/null 2>&1 && ! systemctl is-active --quiet docker; then
      info "Starting Docker service..."
      $SUDO systemctl enable --now docker >/dev/null 2>&1 || true
    fi
  fi

  # Determine whether we need sudo to talk to the Docker daemon in this session
  DOCKER_CMD="docker"
  if ! docker info >/dev/null 2>&1; then
    if [[ -n "$SUDO" ]] && $SUDO docker info >/dev/null 2>&1; then
      DOCKER_CMD="$SUDO docker"
      info "Using elevated Docker permissions for this initial session"
    else
      err "Docker daemon is not responding. Check 'sudo systemctl status docker'."
      exit 1
    fi
  fi

  # Ensure docker compose plugin is available
  if ! $DOCKER_CMD compose version >/dev/null 2>&1; then
    info "Installing Docker Compose plugin..."
    if command -v apt-get >/dev/null 2>&1; then
      $SUDO apt-get update -qq && $SUDO apt-get install -y -qq docker-compose-plugin
    elif command -v dnf >/dev/null 2>&1; then
      $SUDO dnf install -y -q docker-compose-plugin
    fi
  fi
  log "Docker Compose ready ($($DOCKER_CMD compose version --short 2>/dev/null || echo 'v2'))"
}

# -----------------------------------------------------------------------------
# 4. Clone or update repository
# -----------------------------------------------------------------------------
setup_repo() {
  if [[ -f "./docker-compose.yaml" || -f "./docker-compose.yml" ]] && [[ -f "./entrypoint.sh" ]]; then
    INSTALL_DIR="$PWD"
    log "Using existing repository in ${INSTALL_DIR}"
  else
    if [[ -d "${INSTALL_DIR}/.git" ]]; then
      info "Updating existing installation at ${INSTALL_DIR}..."
      git -C "${INSTALL_DIR}" pull --ff-only || true
    elif [[ -d "${INSTALL_DIR}" ]] && [[ -n "$(ls -A "${INSTALL_DIR}" 2>/dev/null)" ]]; then
      if [[ ! -f "${INSTALL_DIR}/docker-compose.yaml" ]]; then
        info "Downloading docker-compose.yaml into ${INSTALL_DIR}..."
        curl -fsSL "https://raw.githubusercontent.com/MrGuato/enshrouded-docker/main/docker-compose.yaml" -o "${INSTALL_DIR}/docker-compose.yaml"
        curl -fsSL "https://raw.githubusercontent.com/MrGuato/enshrouded-docker/main/.env.example" -o "${INSTALL_DIR}/.env.example" || true
      fi
    else
      info "Cloning Enshrouded Docker repository to ${INSTALL_DIR}..."
      git clone --depth 1 "${REPO_URL}" "${INSTALL_DIR}"
    fi
    cd "${INSTALL_DIR}"
    log "Working directory: ${INSTALL_DIR}"
  fi
}

# -----------------------------------------------------------------------------
# 5. Prepare .env configuration and persistent directories
# -----------------------------------------------------------------------------
configure_env() {
  local target_uid target_gid
  target_uid="$(id -u)"
  target_gid="$(id -g)"
  if [[ "$target_uid" -eq 0 ]]; then
    target_uid="${SUDO_UID:-1000}"
    target_gid="${SUDO_GID:-1000}"
  fi

  mkdir -p ./enshrouded-config ./enshrouded-server ./enshrouded-wine
  if [[ "$(id -u)" -eq 0 && "${target_uid}" != "0" ]]; then
    chown -R "${target_uid}:${target_gid}" ./enshrouded-config ./enshrouded-server ./enshrouded-wine
  fi

  if [[ ! -f ".env" ]]; then
    info "Creating .env configuration file..."
    cat > .env <<EOF
# Enshrouded Dedicated Server Configuration
SERVER_NAME="${SERVER_NAME:-My Enshrouded Server}"
SERVER_SLOTS=${SERVER_SLOTS:-16}
SERVER_PASSWORD="${SERVER_PASSWORD:-}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
FRIEND_PASSWORD="${FRIEND_PASSWORD:-}"
GUEST_PASSWORD="${GUEST_PASSWORD:-}"
QUERY_PORT=${QUERY_PORT:-15637}
GAME_PORT=${GAME_PORT:-15637}
ENABLE_VOICE_CHAT=${ENABLE_VOICE_CHAT:-false}
ENABLE_TEXT_CHAT=${ENABLE_TEXT_CHAT:-false}
VOICE_CHAT_MODE="${VOICE_CHAT_MODE:-Proximity}"
GAME_SETTINGS_PRESET="${GAME_SETTINGS_PRESET:-Default}"
UPDATE_ON_START=${UPDATE_ON_START:-1}
SYNC_CONFIG_ON_START=${SYNC_CONFIG_ON_START:-1}
PUID=${PUID:-$target_uid}
PGID=${PGID:-$target_gid}
TZ="${TZ:-$(cat /etc/timezone 2>/dev/null || echo UTC)}"
EOF
    log "Generated ${INSTALL_DIR}/.env"
  else
    log "Keeping existing ${INSTALL_DIR}/.env"
  fi
}

# -----------------------------------------------------------------------------
# 6. Configure Linux Host Firewall (UFW / firewalld) if active
# -----------------------------------------------------------------------------
configure_firewall() {
  local qport="${QUERY_PORT:-15637}"
  if command -v ufw >/dev/null 2>&1 && $SUDO ufw status 2>/dev/null | grep -q "Status: active"; then
    info "UFW firewall is active — opening UDP ports ${qport} and 27015..."
    $SUDO ufw allow "${qport}/udp" comment "Enshrouded Server" >/dev/null 2>&1 || true
    $SUDO ufw allow "27015/udp" comment "Enshrouded Query" >/dev/null 2>&1 || true
    log "UFW rules added for ${qport}/udp and 27015/udp"
  elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld 2>/dev/null; then
    info "firewalld is active — opening UDP ports ${qport} and 27015..."
    $SUDO firewall-cmd --permanent --add-port="${qport}/udp" >/dev/null 2>&1 || true
    $SUDO firewall-cmd --permanent --add-port="27015/udp" >/dev/null 2>&1 || true
    $SUDO firewall-cmd --reload >/dev/null 2>&1 || true
    log "firewalld rules added for ${qport}/udp and 27015/udp"
  fi
}

# -----------------------------------------------------------------------------
# 7. Pull image and launch server
# -----------------------------------------------------------------------------
start_server() {
  info "Pulling latest Enshrouded Docker image from GHCR..."
  $DOCKER_CMD compose pull

  info "Starting Enshrouded Dedicated Server container..."
  $DOCKER_CMD compose up -d
  log "Container 'enshrouded-server' is up and running!"
}

# -----------------------------------------------------------------------------
# 8. Summary & Next Steps
# -----------------------------------------------------------------------------
print_summary() {
  local local_ip public_ip qport
  qport="${QUERY_PORT:-15637}"
  local_ip="$(hostname -I 2>/dev/null | awk '{print $1}' || echo '<your-lan-ip>')"
  public_ip="$(curl -fsSL --max-time 3 https://ifconfig.me 2>/dev/null || echo '<your-public-ip>')"

  echo ""
  echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}${BOLD}   🎉 Enshrouded Dedicated Server Setup Complete!${NC}"
  echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${BOLD}Install Location:${NC}  ${INSTALL_DIR}"
  echo -e "  ${BOLD}Config & Saves:${NC}    ${INSTALL_DIR}/enshrouded-config"
  echo -e "  ${BOLD}LAN Address:${NC}       ${local_ip}:${qport}"
  echo -e "  ${BOLD}Public Address:${NC}    ${public_ip}:${qport} (requires router port-forwarding)"
  echo ""
  echo -e "  ${YELLOW}⏳ First-run note:${NC} SteamCMD is downloading ~6 GB of server files in the"
  echo -e "     background. The server will appear in-game once the download finishes."
  echo ""
  echo -e "  ${BOLD}Useful Commands:${NC}"
  echo -e "    Watch live logs:   ${CYAN}cd ${INSTALL_DIR} && ${DOCKER_CMD} compose logs -f${NC}"
  echo -e "    Edit settings:     ${CYAN}nano ${INSTALL_DIR}/.env && cd ${INSTALL_DIR} && ${DOCKER_CMD} compose up -d${NC}"
  echo -e "    Stop server:       ${CYAN}cd ${INSTALL_DIR} && ${DOCKER_CMD} compose down${NC}"
  echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

check_system_resources
install_base_deps
install_docker
setup_repo
configure_env
configure_firewall
start_server
print_summary