#!/bin/bash
# ============================================================================
# Security Hardening Script
# ============================================================================
# Purpose: Harden server security (SSH, firewall, fail2ban, Docker networking)
# Usage: sudo ./02-security-hardening.sh
# Requirements: Must be run as root (use sudo)
# WARNING: This script modifies SSH config and firewall rules
# ============================================================================

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
echo "  Security Hardening - DevRel Integration"
echo "========================================================================"
echo ""
log_warning "This script will modify security-critical settings:"
echo "  - SSH configuration (disable password auth, root login)"
echo "  - Firewall rules (UFW)"
echo "  - fail2ban configuration"
echo "  - Docker networking (respect firewall)"
echo ""
log_warning "IMPORTANT: Make sure you have SSH key authentication working"
log_warning "before disabling password authentication!"
echo ""
read -p "Continue? (yes/no): " CONFIRM
[ "$CONFIRM" = "yes" ] || exit 0
echo ""

# Step 1: SSH Hardening
log_info "Step 1/5: Hardening SSH configuration..."

# Backup original SSH config
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
if [ -f /etc/ssh/sshd_config ]; then
    cp /etc/ssh/sshd_config "/etc/ssh/sshd_config.backup.${BACKUP_DATE}" || error_exit "Failed to backup SSH config"
    log_success "SSH config backed up to: /etc/ssh/sshd_config.backup.${BACKUP_DATE}"
fi

# Verify current user has SSH key set up
ACTUAL_USER="${SUDO_USER:-$USER}"
if [ "$ACTUAL_USER" != "root" ]; then
    USER_HOME=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)
    if [ ! -f "${USER_HOME}/.ssh/authorized_keys" ]; then
        log_warning "No SSH authorized_keys found for user: ${ACTUAL_USER}"
        log_warning "You may lose SSH access if password authentication is disabled!"
        echo ""
        read -p "Continue anyway? (yes/no): " SSH_CONFIRM
        [ "$SSH_CONFIRM" = "yes" ] || exit 0
    else
        log_info "SSH key found for user: ${ACTUAL_USER}"
    fi
fi

# Apply SSH hardening settings
log_info "Applying SSH security settings..."

# Disable root login
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

# Disable password authentication (key-only)
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config

# Enable public key authentication
sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# Disable empty passwords
sed -i 's/^#*PermitEmptyPasswords.*/PermitEmptyPasswords no/' /etc/ssh/sshd_config

# Disable X11 forwarding
sed -i 's/^#*X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config

# Limit authentication attempts
sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config

# Set client alive interval (disconnect idle sessions)
if ! grep -q "^ClientAliveInterval" /etc/ssh/sshd_config; then
    echo "ClientAliveInterval 300" >> /etc/ssh/sshd_config
fi
if ! grep -q "^ClientAliveCountMax" /etc/ssh/sshd_config; then
    echo "ClientAliveCountMax 2" >> /etc/ssh/sshd_config
fi

# Disable unused authentication methods
if ! grep -q "^ChallengeResponseAuthentication" /etc/ssh/sshd_config; then
    echo "ChallengeResponseAuthentication no" >> /etc/ssh/sshd_config
else
    sed -i 's/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
fi

# Use protocol 2 only
if ! grep -q "^Protocol" /etc/ssh/sshd_config; then
    echo "Protocol 2" >> /etc/ssh/sshd_config
fi

# Validate SSH configuration before restarting
log_info "Validating SSH configuration..."
sshd -t || error_exit "Invalid SSH configuration. Check /etc/ssh/sshd_config"

log_success "SSH configuration updated (service will be restarted at end)"
echo ""

# Step 2: Configure UFW Firewall
log_info "Step 2/5: Configuring UFW firewall..."

# Check if UFW is installed
if ! command -v ufw &> /dev/null; then
    log_info "Installing UFW..."
    apt-get install -y ufw || error_exit "Failed to install UFW"
fi

# Reset UFW to defaults (if not first run)
if ufw status | grep -q "Status: active"; then
    log_info "UFW is active. Resetting to default rules..."
    ufw --force reset
fi

# Set default policies
ufw default deny incoming
ufw default allow outgoing

# Allow SSH (prevent lockout!)
ufw allow ssh comment 'SSH access'

# Allow HTTPS (if using SSL)
ufw allow 443/tcp comment 'HTTPS'

# Allow HTTP (for Let's Encrypt validation, can be removed after SSL setup)
ufw allow 80/tcp comment 'HTTP (Let\'s Encrypt)'

# Do NOT expose application port 3000 publicly - handled by nginx reverse proxy

# Enable UFW
echo "y" | ufw enable || error_exit "Failed to enable UFW"

log_success "UFW firewall configured and enabled"
ufw status verbose
echo ""

# Step 3: Configure Docker to respect UFW
log_info "Step 3/5: Configuring Docker to respect UFW..."

# Check if Docker is installed
if command -v docker &> /dev/null; then
    # Create or update Docker daemon configuration
    DOCKER_DAEMON_CONFIG="/etc/docker/daemon.json"

    if [ -f "${DOCKER_DAEMON_CONFIG}" ]; then
        # Backup existing config
        cp "${DOCKER_DAEMON_CONFIG}" "${DOCKER_DAEMON_CONFIG}.backup.${BACKUP_DATE}" || error_exit "Failed to backup Docker config"
        log_info "Docker config backed up"
    fi

    # Create configuration to make Docker respect UFW
    cat > "${DOCKER_DAEMON_CONFIG}" <<EOF
{
  "iptables": false,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

    log_success "Docker configured to respect UFW"

    # Restart Docker if it's running
    if systemctl is-active --quiet docker; then
        log_info "Restarting Docker daemon..."
        systemctl restart docker || log_warning "Failed to restart Docker"
    fi
else
    log_info "Docker not installed yet - will be configured later"
fi
echo ""

# Step 4: Configure fail2ban
log_info "Step 4/5: Configuring fail2ban..."

# Check if fail2ban is installed
if ! command -v fail2ban-client &> /dev/null; then
    log_info "Installing fail2ban..."
    apt-get install -y fail2ban || error_exit "Failed to install fail2ban"
fi

# Create local jail configuration
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
# Ban time: 1 hour
bantime = 3600

# Find time: 10 minutes
findtime = 600

# Max retry: 5 attempts
maxretry = 5

# Destination email for ban notifications (configure if needed)
# destemail = admin@example.com

# Email sender
# sender = fail2ban@example.com

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[sshd-ddos]
enabled = true
port = ssh
filter = sshd-ddos
logpath = /var/log/auth.log
maxretry = 10
bantime = 600
EOF

# Enable and start fail2ban
systemctl enable fail2ban
systemctl restart fail2ban || error_exit "Failed to start fail2ban"

log_success "fail2ban configured and started"
fail2ban-client status
echo ""

# Step 5: System security settings
log_info "Step 5/5: Applying additional system security settings..."

# Disable IPv6 if not needed (optional, uncomment if desired)
# echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
# echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf

# Enable TCP SYN cookie protection (DDoS mitigation)
echo "net.ipv4.tcp_syncookies = 1" >> /etc/sysctl.conf

# Disable ICMP redirect acceptance (prevent MITM)
echo "net.ipv4.conf.all.accept_redirects = 0" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.accept_redirects = 0" >> /etc/sysctl.conf

# Disable IP source routing (prevent spoofing)
echo "net.ipv4.conf.all.accept_source_route = 0" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.accept_source_route = 0" >> /etc/sysctl.conf

# Enable IP spoofing protection (reverse path filtering)
echo "net.ipv4.conf.all.rp_filter = 1" >> /etc/sysctl.conf
echo "net.ipv4.conf.default.rp_filter = 1" >> /etc/sysctl.conf

# Ignore ICMP ping requests (optional, uncomment if desired)
# echo "net.ipv4.icmp_echo_ignore_all = 1" >> /etc/sysctl.conf

# Apply sysctl settings
sysctl -p || log_warning "Some sysctl settings may require reboot"

log_success "System security settings applied"
echo ""

# Final step: Restart SSH (DANGEROUS - ensure alternate access!)
log_warning "About to restart SSH daemon..."
log_warning "Ensure you have an active SSH session or console access!"
echo ""
read -p "Restart SSH now? (yes/no): " SSH_RESTART
if [ "$SSH_RESTART" = "yes" ]; then
    systemctl restart sshd || error_exit "Failed to restart SSH"
    log_success "SSH daemon restarted"
else
    log_warning "SSH daemon NOT restarted. Run: sudo systemctl restart sshd"
fi
echo ""

# Summary
echo "========================================================================"
log_success "Security hardening completed!"
echo "========================================================================"
echo ""
log_info "Applied security measures:"
echo "  - SSH: Password auth disabled, root login disabled"
echo "  - Firewall: UFW enabled with restrictive rules"
echo "  - Docker: Configured to respect UFW rules"
echo "  - fail2ban: Enabled for SSH brute force protection"
echo "  - Kernel: Network security parameters tuned"
echo ""
log_warning "IMPORTANT:"
echo "  - Test SSH access from another terminal BEFORE closing this session"
echo "  - Firewall rules: Only SSH, HTTP (80), HTTPS (443) allowed"
echo "  - Application port 3000 should ONLY be accessed via nginx reverse proxy"
echo ""
log_info "Next steps:"
echo "  1. Test SSH access with key authentication"
echo "  2. Run: sudo ./03-install-dependencies.sh"
echo ""
