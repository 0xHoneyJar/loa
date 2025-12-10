#!/bin/bash
# ============================================================================
# Install Dependencies Script
# ============================================================================
# Purpose: Install Node.js, PM2, Docker, nginx, and other runtime dependencies
# Usage: sudo ./03-install-dependencies.sh
# Requirements: Must be run as root (use sudo)
# ============================================================================

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
NODE_VERSION="18"  # LTS version
APP_USER="devrel"

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
error_exit() { log_error "$1"; exit 1; }

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error_exit "This script must be run as root (use sudo)"
fi

echo "========================================================================"
echo "  Install Dependencies - DevRel Integration"
echo "========================================================================"
echo ""
log_info "This script will install:"
echo "  - Node.js ${NODE_VERSION}.x (LTS)"
echo "  - npm (Node Package Manager)"
echo "  - PM2 (Process Manager)"
echo "  - Docker and Docker Compose"
echo "  - nginx (Web Server / Reverse Proxy)"
echo ""
read -p "Continue? (yes/no): " CONFIRM
[ "$CONFIRM" = "yes" ] || exit 0
echo ""

# Step 1: Install Node.js
log_info "Step 1/5: Installing Node.js ${NODE_VERSION}.x..."

# Check if Node.js is already installed
if command -v node &> /dev/null; then
    INSTALLED_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
    log_info "Node.js already installed: $(node -v)"

    if [ "$INSTALLED_VERSION" != "$NODE_VERSION" ]; then
        log_warning "Installed version differs from desired version (${NODE_VERSION}.x)"
        read -p "Reinstall Node.js ${NODE_VERSION}.x? (yes/no): " REINSTALL
        if [ "$REINSTALL" != "yes" ]; then
            log_info "Skipping Node.js installation"
            SKIP_NODE=true
        fi
    else
        log_success "Node.js version matches"
        SKIP_NODE=true
    fi
fi

if [ "${SKIP_NODE:-false}" != "true" ]; then
    # Add NodeSource repository
    log_info "Adding NodeSource repository..."
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - || error_exit "Failed to add NodeSource repository"

    # Install Node.js
    log_info "Installing Node.js..."
    apt-get install -y nodejs || error_exit "Failed to install Node.js"

    log_success "Node.js installed: $(node -v)"
    log_success "npm installed: $(npm -v)"
else
    log_info "Using existing Node.js installation"
fi
echo ""

# Step 2: Install PM2
log_info "Step 2/5: Installing PM2 (Process Manager)..."

if command -v pm2 &> /dev/null; then
    log_info "PM2 already installed: $(pm2 -v)"
    read -p "Reinstall PM2? (yes/no): " REINSTALL_PM2
    if [ "$REINSTALL_PM2" = "yes" ]; then
        npm install -g pm2@latest || error_exit "Failed to update PM2"
        log_success "PM2 updated: $(pm2 -v)"
    fi
else
    # Install PM2 globally
    npm install -g pm2@latest || error_exit "Failed to install PM2"
    log_success "PM2 installed: $(pm2 -v)"
fi

# Set up PM2 startup script (systemd)
log_info "Configuring PM2 startup script..."
env PATH=$PATH:/usr/bin pm2 startup systemd -u "${APP_USER}" --hp "/opt/devrel-integration" || log_warning "Failed to setup PM2 startup"

log_success "PM2 configured"
echo ""

# Step 3: Install Docker
log_info "Step 3/5: Installing Docker..."

if command -v docker &> /dev/null; then
    log_info "Docker already installed: $(docker -v)"
    read -p "Reinstall Docker? (yes/no): " REINSTALL_DOCKER
    if [ "$REINSTALL_DOCKER" != "yes" ]; then
        SKIP_DOCKER=true
    fi
fi

if [ "${SKIP_DOCKER:-false}" != "true" ]; then
    # Remove old versions
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    # Install prerequisites
    apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release || error_exit "Failed to install Docker prerequisites"

    # Add Docker's official GPG key
    log_info "Adding Docker GPG key..."
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg || \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg || \
        error_exit "Failed to add Docker GPG key"

    # Add Docker repository
    log_info "Adding Docker repository..."
    DIST=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
    CODENAME=$(lsb_release -cs)

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${DIST} \
      ${CODENAME} stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Update package list
    apt-get update -qq || error_exit "Failed to update package list after adding Docker repo"

    # Install Docker Engine
    log_info "Installing Docker Engine..."
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || error_exit "Failed to install Docker"

    # Add app user to docker group
    usermod -aG docker "${APP_USER}" || error_exit "Failed to add ${APP_USER} to docker group"

    # Start and enable Docker
    systemctl enable docker
    systemctl start docker || error_exit "Failed to start Docker"

    log_success "Docker installed: $(docker -v)"
    log_success "Docker Compose installed: $(docker compose version)"
else
    log_info "Using existing Docker installation"
fi
echo ""

# Step 4: Install nginx
log_info "Step 4/5: Installing nginx..."

if command -v nginx &> /dev/null; then
    log_info "nginx already installed: $(nginx -v 2>&1)"
    read -p "Reinstall nginx? (yes/no): " REINSTALL_NGINX
    if [ "$REINSTALL_NGINX" != "yes" ]; then
        SKIP_NGINX=true
    fi
fi

if [ "${SKIP_NGINX:-false}" != "true" ]; then
    # Install nginx
    apt-get install -y nginx || error_exit "Failed to install nginx"

    # Enable nginx
    systemctl enable nginx
    systemctl start nginx || error_exit "Failed to start nginx"

    log_success "nginx installed: $(nginx -v 2>&1)"
else
    log_info "Using existing nginx installation"
fi
echo ""

# Step 5: Install additional utilities
log_info "Step 5/5: Installing additional utilities..."

apt-get install -y \
    certbot \
    python3-certbot-nginx \
    logrotate \
    rsync \
    gpg \
    || error_exit "Failed to install additional utilities"

log_success "Additional utilities installed"
echo ""

# Verify installations
echo "========================================================================"
log_success "All dependencies installed successfully!"
echo "========================================================================"
echo ""
log_info "Installed versions:"
echo "  Node.js:        $(node -v)"
echo "  npm:            $(npm -v)"
echo "  PM2:            $(pm2 -v)"
echo "  Docker:         $(docker -v | cut -d' ' -f3 | tr -d ',')"
echo "  Docker Compose: $(docker compose version | cut -d' ' -f4)"
echo "  nginx:          $(nginx -v 2>&1 | cut -d' ' -f3 | cut -d'/' -f2)"
echo ""
log_info "Service status:"
systemctl is-active docker && echo "  Docker:  running" || echo "  Docker:  NOT running"
systemctl is-active nginx && echo "  nginx:   running" || echo "  nginx:   NOT running"
echo ""
log_info "Next steps:"
echo "  1. Log out and log back in for docker group to take effect"
echo "  2. Run: sudo ./04-deploy-app.sh"
echo "  3. Run: sudo ./06-setup-ssl.sh (if using domain with SSL)"
echo ""
