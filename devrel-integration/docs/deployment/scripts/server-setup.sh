#!/bin/bash
#
# Onomancer Bot - Server Setup Script
#
# This script sets up a fresh Ubuntu 22.04 server for Onomancer Bot deployment.
# Run as root or with sudo privileges.
#
# Usage: sudo ./server-setup.sh [--domain DOMAIN] [--email EMAIL]
#
# Options:
#   --domain DOMAIN   Domain name for SSL certificate (required for nginx)
#   --email EMAIL     Email for Let's Encrypt notifications
#   --skip-nginx      Skip nginx and SSL setup (for initial testing)
#   --skip-redis      Skip Redis installation
#   --help            Show this help message
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DOMAIN=""
EMAIL=""
SKIP_NGINX=false
SKIP_REDIS=false
APP_USER="devrel"
APP_DIR="/opt/devrel-integration"
LOG_DIR="/var/log/devrel"

# Function definitions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

show_help() {
    head -24 "$0" | tail -20
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --email)
            EMAIL="$2"
            shift 2
            ;;
        --skip-nginx)
            SKIP_NGINX=true
            shift
            ;;
        --skip-redis)
            SKIP_REDIS=true
            shift
            ;;
        --help)
            show_help
            ;;
        *)
            log_error "Unknown option: $1. Use --help for usage."
            ;;
    esac
done

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
fi

echo ""
echo "========================================"
echo "  Onomancer Bot Server Setup Script"
echo "========================================"
echo ""
log_info "Starting server setup..."
log_info "Domain: ${DOMAIN:-'Not specified (nginx will be skipped)'}"
log_info "Email: ${EMAIL:-'Not specified'}"
log_info "Skip Nginx: $SKIP_NGINX"
log_info "Skip Redis: $SKIP_REDIS"
echo ""

# ============================================
# STEP 1: System Update
# ============================================
log_info "Step 1/8: Updating system packages..."
apt update && apt upgrade -y
log_success "System packages updated"

# ============================================
# STEP 2: Install Essential Tools
# ============================================
log_info "Step 2/8: Installing essential tools..."
apt install -y \
    curl \
    git \
    jq \
    htop \
    unzip \
    vim \
    ufw \
    fail2ban \
    ca-certificates \
    gnupg \
    lsb-release

# Set timezone to UTC
timedatectl set-timezone UTC
log_success "Essential tools installed"

# ============================================
# STEP 3: Create Service User
# ============================================
log_info "Step 3/8: Creating service user and directories..."

# Create user if doesn't exist
if ! id "$APP_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$APP_USER"
    log_info "Created user: $APP_USER"
else
    log_info "User $APP_USER already exists"
fi

# Create application directories
mkdir -p "$APP_DIR"/{dist,secrets,data,backups}
mkdir -p "$LOG_DIR"

# Set ownership
chown -R "$APP_USER:$APP_USER" "$APP_DIR"
chown -R "$APP_USER:$APP_USER" "$LOG_DIR"

# Set permissions
chmod 700 "$APP_DIR/secrets"
log_success "Service user and directories created"

# ============================================
# STEP 4: Configure Firewall
# ============================================
log_info "Step 4/8: Configuring firewall..."

# Reset UFW to defaults
ufw --force reset

# Set default policies
ufw default deny incoming
ufw default allow outgoing

# Allow SSH
ufw allow ssh

# Allow HTTP and HTTPS
ufw allow 80/tcp
ufw allow 443/tcp

# Enable firewall
ufw --force enable

log_success "Firewall configured"
log_info "Open ports: 22 (SSH), 80 (HTTP), 443 (HTTPS)"

# ============================================
# STEP 5: Configure Fail2ban
# ============================================
log_info "Step 5/8: Configuring fail2ban..."

# Create local jail configuration
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
backend = systemd

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF

# Restart fail2ban
systemctl enable fail2ban
systemctl restart fail2ban

log_success "Fail2ban configured and started"

# ============================================
# STEP 6: Install Node.js
# ============================================
log_info "Step 6/8: Installing Node.js 20 LTS..."

# Add NodeSource repository
if [ ! -f /etc/apt/sources.list.d/nodesource.list ]; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
fi

apt install -y nodejs

# Verify installation
NODE_VERSION=$(node --version)
NPM_VERSION=$(npm --version)
log_info "Node.js version: $NODE_VERSION"
log_info "npm version: $NPM_VERSION"

# Install PM2 globally
npm install -g pm2

log_success "Node.js and PM2 installed"

# ============================================
# STEP 7: Install Redis (Optional)
# ============================================
if [ "$SKIP_REDIS" = false ]; then
    log_info "Step 7/8: Installing Redis..."

    apt install -y redis-server

    # Configure Redis for local access only
    sed -i 's/^bind .*/bind 127.0.0.1/' /etc/redis/redis.conf
    sed -i 's/^# maxmemory .*/maxmemory 256mb/' /etc/redis/redis.conf
    sed -i 's/^# maxmemory-policy .*/maxmemory-policy allkeys-lru/' /etc/redis/redis.conf

    # Enable and start Redis
    systemctl enable redis-server
    systemctl restart redis-server

    log_success "Redis installed and configured"
else
    log_info "Step 7/8: Skipping Redis installation"
fi

# ============================================
# STEP 8: Install and Configure Nginx
# ============================================
if [ "$SKIP_NGINX" = false ] && [ -n "$DOMAIN" ]; then
    log_info "Step 8/8: Installing Nginx and SSL..."

    apt install -y nginx certbot python3-certbot-nginx

    # Create nginx site configuration
    cat > /etc/nginx/sites-available/onomancer << EOF
# Onomancer Bot - Nginx Configuration
# Generated by server-setup.sh

# Rate limiting zone
limit_req_zone \$binary_remote_addr zone=api_limit:10m rate=10r/s;

server {
    listen 80;
    server_name $DOMAIN;

    # Redirect all HTTP to HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    # SSL configuration (will be updated by certbot)
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;

    # Modern TLS configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # HSTS
    add_header Strict-Transport-Security "max-age=63072000" always;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Proxy to Node.js application
    location / {
        limit_req zone=api_limit burst=20 nodelay;

        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;

        # Timeouts for long-running operations
        proxy_connect_timeout 60s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
    }

    # Health check endpoint (no rate limiting)
    location /health {
        proxy_pass http://127.0.0.1:3000/health;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        access_log off;
    }
}
EOF

    # Enable site
    ln -sf /etc/nginx/sites-available/onomancer /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default

    # Test nginx configuration
    nginx -t

    # Obtain SSL certificate
    if [ -n "$EMAIL" ]; then
        certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "$EMAIL" --redirect
    else
        certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email --redirect
    fi

    # Enable and start nginx
    systemctl enable nginx
    systemctl restart nginx

    log_success "Nginx installed with SSL for $DOMAIN"
else
    log_info "Step 8/8: Skipping Nginx setup (no domain specified or --skip-nginx)"
    log_warn "You can run this script again with --domain to set up nginx later"
fi

# ============================================
# STEP 9: Configure PM2 for Service User
# ============================================
log_info "Setting up PM2 for service user..."

# Set PM2_HOME for the service user
su - "$APP_USER" -c "mkdir -p $APP_DIR/.pm2"

# Add PM2_HOME to bashrc
if ! grep -q "PM2_HOME" "/home/$APP_USER/.bashrc"; then
    echo "export PM2_HOME=$APP_DIR/.pm2" >> "/home/$APP_USER/.bashrc"
fi

# Configure PM2 startup
PM2_HOME="$APP_DIR/.pm2" pm2 startup systemd -u "$APP_USER" --hp "/home/$APP_USER"

log_success "PM2 configured for $APP_USER"

# ============================================
# STEP 10: Create Log Rotation
# ============================================
log_info "Configuring log rotation..."

cat > /etc/logrotate.d/devrel << EOF
$LOG_DIR/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 $APP_USER $APP_USER
    sharedscripts
    postrotate
        PM2_HOME=$APP_DIR/.pm2 pm2 reloadLogs > /dev/null 2>&1 || true
    endscript
}
EOF

log_success "Log rotation configured"

# ============================================
# Summary
# ============================================
echo ""
echo "========================================"
echo "  Server Setup Complete!"
echo "========================================"
echo ""
log_success "All components installed successfully"
echo ""
echo "Summary:"
echo "  - User:         $APP_USER"
echo "  - App Directory: $APP_DIR"
echo "  - Log Directory: $LOG_DIR"
echo "  - Node.js:      $(node --version)"
echo "  - PM2:          $(pm2 --version)"
if [ "$SKIP_REDIS" = false ]; then
    echo "  - Redis:        $(redis-server --version | cut -d'=' -f2 | cut -d' ' -f1)"
fi
if [ "$SKIP_NGINX" = false ] && [ -n "$DOMAIN" ]; then
    echo "  - Nginx:        Configured for $DOMAIN"
    echo "  - SSL:          Let's Encrypt certificate installed"
fi
echo ""
echo "Next steps:"
echo "  1. Copy your application files to $APP_DIR/"
echo "  2. Copy secrets to $APP_DIR/secrets/"
echo "  3. Run the deploy script: ./deploy.sh"
echo ""
echo "Firewall status:"
ufw status
echo ""
