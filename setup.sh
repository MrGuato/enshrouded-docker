#!/usr/bin/env bash
# One-shot installer for a fresh Linux host: installs Docker if needed, clones this repo into
# ~/enshrouded-docker, asks for the server name, slots and passwords, opens the firewall and
# starts the server.
#
#   curl -fsSL https://raw.githubusercontent.com/MrGuato/enshrouded-docker/main/setup.sh | bash
#
# Anything set on the bash side of the pipe is used instead of asking; NONINTERACTIVE=1 asks
# nothing and generates a password:
#   curl -fsSL .../setup.sh | SERVER_NAME="Our World" SERVER_PASSWORD="secret" bash
set -euo pipefail

REPO_URL="https://github.com/MrGuato/enshrouded-docker.git"
INSTALL_DIR="${INSTALL_DIR:-$HOME/enshrouded-docker}"
QUERY_PORT="${QUERY_PORT:-15637}"

log()  { echo "[setup] $*"; }
warn() { echo "[setup] WARNING: $*"; }
die()  { echo "[setup] ERROR: $*" >&2; exit 1; }

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    command -v sudo >/dev/null 2>&1 || die "Run this as root or install sudo."
    SUDO="sudo"
fi

check_resources() {
    local free_gb mem_mb
    free_gb="$(df -BG "$HOME" 2>/dev/null | awk 'NR==2 {gsub("G","",$4); print $4}')"
    if [[ "$free_gb" =~ ^[0-9]+$ ]] && [ "$free_gb" -lt 12 ]; then
        warn "About ${free_gb} GB free. The game files and Wine need roughly 12 GB."
    fi
    mem_mb="$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)"
    if [[ "$mem_mb" =~ ^[0-9]+$ ]] && [ "$mem_mb" -gt 0 ] && [ "$mem_mb" -lt 7500 ]; then
        warn "${mem_mb} MB of RAM. Enshrouded wants 8 GB or more (or a swap file)."
    fi
    if [ "$(uname -m)" != "x86_64" ]; then
        warn "This host is $(uname -m). The image is x86_64 only (the server runs under Wine)."
    fi
}

install_packages() {   # install_packages pkg...
    if command -v apt-get >/dev/null 2>&1; then
        $SUDO apt-get update -qq && $SUDO apt-get install -y -qq "$@"
    elif command -v dnf >/dev/null 2>&1; then
        $SUDO dnf install -y -q "$@"
    elif command -v pacman >/dev/null 2>&1; then
        $SUDO pacman -Sy --noconfirm "$@"
    else
        die "No supported package manager found. Install $* by hand."
    fi
}

install_docker() {
    if ! command -v git >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
        log "Installing git and curl"
        install_packages git curl ca-certificates
    fi

    if ! command -v docker >/dev/null 2>&1; then
        log "Installing Docker Engine (get.docker.com)"
        curl -fsSL https://get.docker.com | $SUDO sh
        if [ "$(id -u)" -ne 0 ]; then $SUDO usermod -aG docker "${USER:-$(id -un)}" || true; fi
    fi
    if command -v systemctl >/dev/null 2>&1; then $SUDO systemctl enable --now docker >/dev/null 2>&1 || true; fi

    # A user just added to the docker group only gets it on the next login; use sudo until then.
    DOCKER="docker"
    if ! docker info >/dev/null 2>&1; then
        [ -n "$SUDO" ] && $SUDO docker info >/dev/null 2>&1 || die "The Docker daemon is not responding. Check: sudo systemctl status docker"
        DOCKER="sudo docker"
    fi
    if ! $DOCKER compose version >/dev/null 2>&1; then
        log "Installing the Docker Compose plugin"
        install_packages docker-compose-plugin
    fi
    export DOCKER
    log "Docker ready ($($DOCKER compose version --short 2>/dev/null || echo 'compose v2'))"
}

get_repo() {
    if [ -x ./enshrouded ] && [ -f ./docker-compose.yaml ]; then
        INSTALL_DIR="$PWD"
    elif [ -d "$INSTALL_DIR/.git" ]; then
        log "Updating $INSTALL_DIR"
        git -C "$INSTALL_DIR" pull --ff-only || warn "git pull failed, keeping the current checkout"
    elif [ -e "$INSTALL_DIR" ] && [ -n "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
        die "$INSTALL_DIR exists and is not a clone of this repo. Move it, or set INSTALL_DIR to another folder."
    else
        log "Cloning into $INSTALL_DIR"
        git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
    fi
    cd "$INSTALL_DIR"
}

open_firewall() {
    if command -v ufw >/dev/null 2>&1 && $SUDO ufw status 2>/dev/null | grep -q "Status: active"; then
        log "Opening ${QUERY_PORT}/udp in ufw"
        $SUDO ufw allow "${QUERY_PORT}/udp" comment "Enshrouded" >/dev/null || true
    elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld 2>/dev/null; then
        log "Opening ${QUERY_PORT}/udp in firewalld"
        $SUDO firewall-cmd --permanent --add-port="${QUERY_PORT}/udp" >/dev/null || true
        $SUDO firewall-cmd --reload >/dev/null || true
    fi
}

env_value() {   # env_value KEY -> value from .env without quotes
    sed -n "s/^$1=//p" .env 2>/dev/null | head -n 1 | sed -e "s/^'\(.*\)'\$/\1/" -e 's/^"\(.*\)"$/\1/'
}

run_setup() {
    if [ -f .env ]; then
        log "Keeping the existing .env"
    elif [ "${NONINTERACTIVE:-0}" != "1" ] && (: < /dev/tty) 2>/dev/null; then
        # stdin is this script under curl | bash, so the questions go to the terminal
        ./enshrouded setup < /dev/tty
    else
        ./enshrouded setup --yes < /dev/null
    fi
}

summary() {
    local lan public name players admin
    lan="$(hostname -I 2>/dev/null | awk '{print $1}')"
    public="$(curl -fsSL --max-time 3 https://ifconfig.me 2>/dev/null || true)"
    name="$(env_value SERVER_NAME)"
    admin="$(env_value ADMIN_PASSWORD)"
    players="$(env_value SERVER_PASSWORD)"
    if [ -z "$players" ]; then players="$(env_value FRIEND_PASSWORD)"; fi
    cat <<EOF

[setup] Done. The server is starting in $INSTALL_DIR
[setup] The first start downloads about 6 GB of game files. It is ready when the log shows
[setup]   [Session] 'HostOnline' (up)
[setup]
[setup] Server name:     ${name}
[setup] Password:        ${players:-<none>}
EOF
    if [ -n "$admin" ]; then echo "[setup] Admin password:  $admin"; fi
    cat <<EOF
[setup] LAN address:     ${lan:-<lan-ip>}:${QUERY_PORT}
[setup] Public address:  ${public:-<public-ip>}:${QUERY_PORT} (forward ${QUERY_PORT}/udp on your router)
[setup] Passwords and settings live in $INSTALL_DIR/.env
[setup]
[setup] cd $INSTALL_DIR
[setup] ./enshrouded logs      follow the log
[setup] ./enshrouded status    health and session state
[setup] ./enshrouded help      everything else
EOF
    if [ "$DOCKER" != "docker" ]; then
        echo "[setup] Log out and back in once so your user can run Docker without sudo."
        echo "[setup] Until then, prefix commands with DOCKER=\"sudo docker\", e.g. DOCKER=\"sudo docker\" ./enshrouded logs"
    fi
}

# Everything runs from main so bash has read the whole script before any command starts;
# with curl | bash, a command that reads stdin would otherwise swallow the rest of the script.
main() {
    log "Enshrouded Dedicated Server installer by MrGuato"
    check_resources
    install_docker
    get_repo
    run_setup
    open_firewall
    ./enshrouded start --no-follow < /dev/null
    summary
}

main "$@"
