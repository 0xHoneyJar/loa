#!/bin/bash
# ============================================================================
# Setup Monitoring Script
# ============================================================================
# Purpose: Set up basic monitoring with Uptime Kuma (lightweight, self-hosted)
# Usage: sudo ./05-setup-monitoring.sh
# Requirements: Must be run as root (use sudo), Docker must be installed
# ============================================================================

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
MONITORING_PORT="3002"
MONITORING_DATA_DIR="/opt/monitoring-data"

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
echo "  Setup Monitoring - Uptime Kuma"
echo "========================================================================"
echo ""
log_info "This script will install Uptime Kuma for monitoring:"
echo "  - Self-hosted uptime monitoring"
echo "  - Health check monitoring for DevRel bot"
echo "  - Notification support (Discord, Slack, email, etc.)"
echo "  - Web UI on port ${MONITORING_PORT}"
echo ""
log_warning "Note: This is a basic monitoring setup."
log_info "For production, consider: Prometheus + Grafana, Datadog, or New Relic"
echo ""
read -p "Continue? (yes/no): " CONFIRM
[ "$CONFIRM" = "yes" ] || exit 0
echo ""

# Step 1: Check Docker
log_info "Step 1/4: Checking Docker installation..."

if ! command -v docker &> /dev/null; then
    error_exit "Docker not installed. Run: sudo ./03-install-dependencies.sh"
fi

if ! docker info &> /dev/null; then
    error_exit "Docker daemon not running. Start with: sudo systemctl start docker"
fi

log_success "Docker is ready"
echo ""

# Step 2: Create data directory
log_info "Step 2/4: Creating data directory..."

mkdir -p "${MONITORING_DATA_DIR}" || error_exit "Failed to create ${MONITORING_DATA_DIR}"
chown -R 1000:1000 "${MONITORING_DATA_DIR}" || log_warning "Failed to set ownership"

log_success "Data directory created: ${MONITORING_DATA_DIR}"
echo ""

# Step 3: Deploy Uptime Kuma
log_info "Step 3/4: Deploying Uptime Kuma container..."

# Stop existing container if running
if docker ps -a --format '{{.Names}}' | grep -q "uptime-kuma"; then
    log_info "Stopping existing Uptime Kuma container..."
    docker stop uptime-kuma || true
    docker rm uptime-kuma || true
fi

# Run Uptime Kuma container
docker run -d \
    --name uptime-kuma \
    --restart always \
    -p 127.0.0.1:${MONITORING_PORT}:3001 \
    -v "${MONITORING_DATA_DIR}:/app/data" \
    louislam/uptime-kuma:latest || error_exit "Failed to start Uptime Kuma"

log_success "Uptime Kuma container started"
echo ""

# Step 4: Wait for startup
log_info "Step 4/4: Waiting for Uptime Kuma to start..."

MAX_WAIT=60
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    if curl -sf http://localhost:${MONITORING_PORT} > /dev/null; then
        log_success "Uptime Kuma is ready!"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    echo -n "."
done
echo ""

if [ $ELAPSED -ge $MAX_WAIT ]; then
    log_error "Uptime Kuma did not start within ${MAX_WAIT} seconds"
    log_info "Check logs: docker logs uptime-kuma"
    exit 1
fi
echo ""

# Summary
echo "========================================================================"
log_success "Monitoring setup completed!"
echo "========================================================================"
echo ""
log_info "Uptime Kuma details:"
echo "  Web UI: http://localhost:${MONITORING_PORT}"
echo "  Data directory: ${MONITORING_DATA_DIR}"
echo "  Container: uptime-kuma"
echo ""
log_info "First-time setup:"
echo "  1. Open http://localhost:${MONITORING_PORT} in browser"
echo "  2. Create admin account (first user becomes admin)"
echo "  3. Add monitor for DevRel bot:"
echo "     - Type: HTTP(s)"
echo "     - URL: http://localhost:3000/health"
echo "     - Interval: 60 seconds"
echo "     - Retry: 3 times"
echo "  4. Set up notifications (Discord webhook recommended)"
echo ""
log_info "Useful commands:"
echo "  View logs:     docker logs uptime-kuma"
echo "  Restart:       docker restart uptime-kuma"
echo "  Stop:          docker stop uptime-kuma"
echo "  Start:         docker start uptime-kuma"
echo ""
log_warning "Access the Web UI:"
echo "  - Locally: http://localhost:${MONITORING_PORT}"
echo "  - Remotely: Use SSH tunnel: ssh -L 3002:localhost:3002 user@server"
echo "  - Or configure nginx reverse proxy with authentication"
echo ""
