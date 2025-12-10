#!/bin/bash
# ============================================================================
# Initial Server Setup Script
# ============================================================================
# Purpose: Initial system setup and user creation for DevRel integration
# Usage: sudo ./01-initial-setup.sh
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
APP_USER="devrel"
APP_GROUP="devrel"
APP_DIR="/opt/devrel-integration"
LOG_DIR="/var/log/devrel"
DATA_DIR="/var/lib/devrel-integration"

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

# Capture the actual user who invoked sudo
ACTUAL_USER="${SUDO_USER:-$USER}"
if [ "$ACTUAL_USER" = "root" ]; then
    log_warning "Running directly as root. Consider using sudo from a regular user account."
fi

echo "========================================================================"
echo "  Initial Server Setup - DevRel Integration"
echo "========================================================================"
echo ""
log_info "This script will:"
echo "  - Update system packages"
echo "  - Create application user and group"
echo "  - Set up directory structure"
echo "  - Install essential system utilities"
echo ""
read -p "Continue? (yes/no): " CONFIRM
[ "$CONFIRM" = "yes" ] || exit 0
echo ""

# Step 1: Update system packages
log_info "Step 1/6: Updating system packages..."
apt-get update -qq || error_exit "Failed to update package list"
log_success "Package list updated"
echo ""

# Step 2: Install essential utilities
log_info "Step 2/6: Installing essential system utilities..."
apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    ufw \
    fail2ban \
    unattended-upgrades \
    jq \
    htop \
    vim \
    || error_exit "Failed to install system utilities"

log_success "System utilities installed"
echo ""

# Step 3: Create application user and group
log_info "Step 3/6: Creating application user and group..."

# Create group if it doesn't exist
if ! getent group "${APP_GROUP}" > /dev/null 2>&1; then
    groupadd --system "${APP_GROUP}" || error_exit "Failed to create group ${APP_GROUP}"
    log_success "Created group: ${APP_GROUP}"
else
    log_info "Group already exists: ${APP_GROUP}"
fi

# Create user if it doesn't exist
if ! id -u "${APP_USER}" > /dev/null 2>&1; then
    useradd \
        --system \
        --gid "${APP_GROUP}" \
        --shell /bin/bash \
        --home-dir "${APP_DIR}" \
        --create-home \
        --comment "DevRel Integration Bot" \
        "${APP_USER}" || error_exit "Failed to create user ${APP_USER}"
    log_success "Created user: ${APP_USER}"
else
    log_info "User already exists: ${APP_USER}"
fi

echo ""

# Step 4: Create directory structure
log_info "Step 4/6: Creating directory structure..."

# Application directory
if [ ! -d "${APP_DIR}" ]; then
    mkdir -p "${APP_DIR}" || error_exit "Failed to create ${APP_DIR}"
    log_success "Created: ${APP_DIR}"
else
    log_info "Directory exists: ${APP_DIR}"
fi

# Create subdirectories
for dir in config secrets logs data backups scripts; do
    if [ ! -d "${APP_DIR}/${dir}" ]; then
        mkdir -p "${APP_DIR}/${dir}" || error_exit "Failed to create ${APP_DIR}/${dir}"
        log_success "Created: ${APP_DIR}/${dir}"
    else
        log_info "Directory exists: ${APP_DIR}/${dir}"
    fi
done

# System log directory
if [ ! -d "${LOG_DIR}" ]; then
    mkdir -p "${LOG_DIR}" || error_exit "Failed to create ${LOG_DIR}"
    log_success "Created: ${LOG_DIR}"
else
    log_info "Directory exists: ${LOG_DIR}"
fi

# System data directory
if [ ! -d "${DATA_DIR}" ]; then
    mkdir -p "${DATA_DIR}" || error_exit "Failed to create ${DATA_DIR}"
    log_success "Created: ${DATA_DIR}"
else
    log_info "Directory exists: ${DATA_DIR}"
fi

echo ""

# Step 5: Set proper ownership
log_info "Step 5/6: Setting directory ownership..."

chown -R "${APP_USER}:${APP_GROUP}" "${APP_DIR}" || error_exit "Failed to set ownership for ${APP_DIR}"
chown -R "${APP_USER}:${APP_GROUP}" "${LOG_DIR}" || error_exit "Failed to set ownership for ${LOG_DIR}"
chown -R "${APP_USER}:${APP_GROUP}" "${DATA_DIR}" || error_exit "Failed to set ownership for ${DATA_DIR}"

log_success "Ownership set to ${APP_USER}:${APP_GROUP}"
echo ""

# Step 6: Set proper permissions
log_info "Step 6/6: Setting directory permissions..."

# Application directory - owner full access, group read, no world access
chmod 750 "${APP_DIR}" || error_exit "Failed to set permissions for ${APP_DIR}"

# Secrets directory - owner only
chmod 700 "${APP_DIR}/secrets" || error_exit "Failed to set permissions for secrets"

# Logs directory - owner full, group read
chmod 750 "${LOG_DIR}" || error_exit "Failed to set permissions for logs"

# Data directory - owner full access
chmod 750 "${DATA_DIR}" || error_exit "Failed to set permissions for data"

# Backups directory - owner only
chmod 700 "${APP_DIR}/backups" || error_exit "Failed to set permissions for backups"

log_success "Permissions configured"
echo ""

# Step 7: Configure automatic security updates
log_info "Configuring automatic security updates..."
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::InstallOnShutdown "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

log_success "Automatic security updates configured"
echo ""

# Summary
echo "========================================================================"
log_success "Initial setup completed successfully!"
echo "========================================================================"
echo ""
log_info "Summary:"
echo "  Application user:  ${APP_USER}"
echo "  Application group: ${APP_GROUP}"
echo "  Application dir:   ${APP_DIR}"
echo "  Log directory:     ${LOG_DIR}"
echo "  Data directory:    ${DATA_DIR}"
echo ""
log_info "Next steps:"
echo "  1. Run: sudo ./02-security-hardening.sh"
echo "  2. Run: sudo ./03-install-dependencies.sh"
echo "  3. Deploy application code to ${APP_DIR}"
echo ""
