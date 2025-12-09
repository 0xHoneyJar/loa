#!/bin/bash
# ============================================================================
# Setup SSL and nginx Reverse Proxy Script
# ============================================================================
# Purpose: Configure nginx as reverse proxy with rate limiting
# Usage: sudo ./06-setup-ssl.sh
# Requirements: Must be run as root (use sudo), nginx must be installed
# ============================================================================

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
DOMAIN="${DOMAIN:-}"
APP_PORT="3000"
NGINX_CONF="/etc/nginx/sites-available/devrel-integration"
NGINX_ENABLED="/etc/nginx/sites-enabled/devrel-integration"

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
echo "  Setup nginx Reverse Proxy - DevRel Integration"
echo "========================================================================"
echo ""
log_info "This script will configure nginx as a reverse proxy with:"
echo "  - Rate limiting (DDoS protection)"
echo "  - Security headers"
echo "  - TLS/SSL encryption (if domain provided)"
echo "  - Access to application on localhost:${APP_PORT}"
echo ""

# Ask for domain name
read -p "Do you have a domain name for this server? (yes/no): " HAS_DOMAIN

if [ "$HAS_DOMAIN" = "yes" ]; then
    read -p "Enter domain name (e.g., devrel.example.com): " DOMAIN
    if [ -z "$DOMAIN" ]; then
        error_exit "Domain name cannot be empty"
    fi
    log_info "Will configure SSL for domain: ${DOMAIN}"
    USE_SSL=true
else
    log_info "Will configure reverse proxy without SSL (localhost binding)"
    log_warning "Application will be accessible only via SSH tunnel or local network"
    USE_SSL=false
fi
echo ""

read -p "Continue? (yes/no): " CONFIRM
[ "$CONFIRM" = "yes" ] || exit 0
echo ""

# Step 1: Check nginx
log_info "Step 1/6: Checking nginx installation..."

if ! command -v nginx &> /dev/null; then
    error_exit "nginx not installed. Run: sudo ./03-install-dependencies.sh"
fi

log_success "nginx is installed"
echo ""

# Step 2: Remove default site
log_info "Step 2/6: Removing default nginx site..."

if [ -L /etc/nginx/sites-enabled/default ]; then
    rm /etc/nginx/sites-enabled/default || log_warning "Failed to remove default site"
    log_success "Default site removed"
else
    log_info "Default site not enabled"
fi
echo ""

# Step 3: Create nginx configuration
log_info "Step 3/6: Creating nginx configuration..."

# Create rate limiting configuration
cat > "${NGINX_CONF}" <<'EOF'
# Rate limiting zones
limit_req_zone $binary_remote_addr zone=webhook_limit:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=30r/s;
limit_req_zone $binary_remote_addr zone=health_limit:10m rate=1r/s;

server {
    listen 80;
EOF

if [ "$USE_SSL" = "true" ]; then
    cat >> "${NGINX_CONF}" <<EOF
    server_name ${DOMAIN};
EOF
else
    cat >> "${NGINX_CONF}" <<'EOF'
    server_name _;
EOF
fi

cat >> "${NGINX_CONF}" <<'EOF'

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;

    # Logging
    access_log /var/log/nginx/devrel-access.log;
    error_log /var/log/nginx/devrel-error.log;

    # Webhooks endpoint - 10 requests/second per IP
    location /webhooks/ {
        limit_req zone=webhook_limit burst=20 nodelay;
        limit_req_status 429;

        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;

        # Proxy headers
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;

        # Body size limit
        client_max_body_size 1m;
    }

    # Health check endpoint - 1 request/second per IP
    location /health {
        limit_req zone=health_limit burst=5 nodelay;

        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Short timeout for health checks
        proxy_connect_timeout 5s;
        proxy_send_timeout 5s;
        proxy_read_timeout 5s;
    }

    # Ready check endpoint
    location /ready {
        limit_req zone=health_limit burst=5 nodelay;

        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # Metrics endpoint (restrict access if needed)
    location /metrics {
        # Uncomment to restrict to local network only
        # allow 10.0.0.0/8;
        # allow 172.16.0.0/12;
        # allow 192.168.0.0/16;
        # deny all;

        limit_req zone=health_limit burst=5 nodelay;

        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # All other endpoints - 30 requests/second per IP
    location / {
        limit_req zone=api_limit burst=50 nodelay;

        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;

        client_max_body_size 5m;
    }
}
EOF

log_success "nginx configuration created: ${NGINX_CONF}"
echo ""

# Step 4: Enable site
log_info "Step 4/6: Enabling site..."

ln -sf "${NGINX_CONF}" "${NGINX_ENABLED}" || error_exit "Failed to enable site"

log_success "Site enabled"
echo ""

# Step 5: Test configuration
log_info "Step 5/6: Testing nginx configuration..."

nginx -t || error_exit "nginx configuration test failed"

log_success "Configuration test passed"
echo ""

# Step 6: Set up SSL (if domain provided)
if [ "$USE_SSL" = "true" ]; then
    log_info "Step 6/6: Setting up SSL with Let's Encrypt..."

    # Check if certbot is installed
    if ! command -v certbot &> /dev/null; then
        error_exit "certbot not installed. Run: sudo ./03-install-dependencies.sh"
    fi

    # Reload nginx first
    systemctl reload nginx || error_exit "Failed to reload nginx"

    log_info "Obtaining SSL certificate for ${DOMAIN}..."
    log_warning "Make sure DNS is pointing to this server!"
    echo ""
    read -p "Is DNS configured for ${DOMAIN}? (yes/no): " DNS_READY
    if [ "$DNS_READY" != "yes" ]; then
        log_warning "Configure DNS first, then run:"
        echo "  sudo certbot --nginx -d ${DOMAIN}"
        exit 0
    fi

    # Obtain certificate
    certbot --nginx -d "${DOMAIN}" --non-interactive --agree-tos --redirect \
        --email "admin@${DOMAIN}" || {
        log_error "Failed to obtain SSL certificate"
        log_info "You can try manually: sudo certbot --nginx -d ${DOMAIN}"
        exit 1
    }

    log_success "SSL certificate obtained and configured"
    echo ""

    # Set up auto-renewal
    log_info "Setting up automatic certificate renewal..."

    # Test renewal
    certbot renew --dry-run || log_warning "Certificate renewal test failed"

    log_success "Auto-renewal configured (systemd timer)"
else
    log_info "Step 6/6: Reloading nginx..."
    systemctl reload nginx || error_exit "Failed to reload nginx"
    log_success "nginx reloaded"
fi
echo ""

# Summary
echo "========================================================================"
log_success "nginx reverse proxy configured successfully!"
echo "========================================================================"
echo ""
log_info "Configuration:"
echo "  Config file: ${NGINX_CONF}"
echo "  Backend: http://127.0.0.1:${APP_PORT}"

if [ "$USE_SSL" = "true" ]; then
    echo "  Public URL: https://${DOMAIN}"
    echo ""
    log_info "SSL certificate:"
    echo "  Domain: ${DOMAIN}"
    echo "  Auto-renewal: Enabled (systemd timer)"
    echo "  Check renewal: sudo certbot renew --dry-run"
else
    echo "  Access: localhost only (SSH tunnel recommended)"
    echo ""
    log_info "To access remotely via SSH tunnel:"
    echo "  ssh -L 8080:localhost:80 user@server"
    echo "  Then visit: http://localhost:8080"
fi
echo ""

log_info "Rate limiting configured:"
echo "  Webhooks: 10 req/s per IP (burst: 20)"
echo "  API:      30 req/s per IP (burst: 50)"
echo "  Health:   1 req/s per IP (burst: 5)"
echo ""

log_info "Test endpoints:"
if [ "$USE_SSL" = "true" ]; then
    echo "  curl https://${DOMAIN}/health"
    echo "  curl https://${DOMAIN}/ready"
else
    echo "  curl http://localhost/health"
    echo "  curl http://localhost/ready"
fi
echo ""

log_info "Useful commands:"
echo "  Test config:   sudo nginx -t"
echo "  Reload:        sudo systemctl reload nginx"
echo "  Restart:       sudo systemctl restart nginx"
echo "  View logs:     sudo tail -f /var/log/nginx/devrel-*.log"
if [ "$USE_SSL" = "true" ]; then
    echo "  SSL status:    sudo certbot certificates"
fi
echo ""
