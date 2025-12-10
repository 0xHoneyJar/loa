#!/bin/bash
# ============================================================================
# Production Deployment Script
# ============================================================================
# Purpose: Deploy agentic-base integration to production environment
# Usage: ./scripts/deploy-production.sh
# WARNING: This script deploys to PRODUCTION. Use with caution!
# ============================================================================

set -euo pipefail  # Exit on error, undefined variable, or pipe failure

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="docker-compose.prod.yml"
IMAGE_NAME="agentic-base-integration:latest"
CONTAINER_NAME="agentic-base-bot-prod"
BACKUP_DIR="${PROJECT_DIR}/backups"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handler
error_exit() {
    log_error "$1"
    log_error "Production deployment failed!"
    log_info "To rollback, run: ./scripts/rollback-production.sh"
    exit 1
}

# Print header with warning
echo "========================================================================"
echo -e "${BOLD}${RED}  PRODUCTION DEPLOYMENT${NC}"
echo "  Agentic-Base Integration"
echo "========================================================================"
echo ""
log_warning "This script will deploy to PRODUCTION environment!"
log_warning "Make sure you have:"
log_warning "  1. Tested thoroughly in staging"
log_warning "  2. Backed up production data"
log_warning "  3. Notified relevant stakeholders"
log_warning "  4. Have a rollback plan ready"
echo ""

# Confirmation prompt
read -p "Do you want to proceed with production deployment? (yes/no): " CONFIRM
if [ "${CONFIRM}" != "yes" ]; then
    log_info "Deployment cancelled by user"
    exit 0
fi
echo ""

# Step 1: Pre-deployment checks
log_info "Step 1/9: Running pre-deployment checks..."

# Check if running from correct directory
cd "${PROJECT_DIR}" || error_exit "Failed to change to project directory"

# Check if Docker is installed and running
if ! command -v docker &> /dev/null; then
    error_exit "Docker is not installed"
fi

if ! docker info &> /dev/null; then
    error_exit "Docker daemon is not running"
fi

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null; then
    error_exit "docker-compose is not installed"
fi

# Check if production secrets file exists
if [ ! -f "secrets/.env.production" ]; then
    error_exit "Production secrets file not found: secrets/.env.production"
fi

# Verify secrets file permissions
SECRETS_PERMS=$(stat -c "%a" secrets/.env.production 2>/dev/null || stat -f "%A" secrets/.env.production 2>/dev/null)
if [ "${SECRETS_PERMS}" != "600" ]; then
    log_error "Production secrets have insecure permissions: ${SECRETS_PERMS}"
    error_exit "Fix permissions with: chmod 600 secrets/.env.production"
fi

log_success "Pre-deployment checks passed"
echo ""

# Step 2: Backup current state
log_info "Step 2/9: Backing up current state..."

# Create backup directory
mkdir -p "${BACKUP_DIR}"

# Backup timestamp
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/backup_${BACKUP_TIMESTAMP}"

# Create backup directory for this deployment
mkdir -p "${BACKUP_PATH}"

# Backup data directory (database, user preferences)
if [ -d "data" ]; then
    log_info "Backing up data directory..."
    cp -r data "${BACKUP_PATH}/data" || log_warning "Failed to backup data directory"
fi

# Backup configuration
if [ -d "config" ]; then
    log_info "Backing up configuration..."
    cp -r config "${BACKUP_PATH}/config" || log_warning "Failed to backup config directory"
fi

# Save current container state
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_info "Recording current container state..."
    docker inspect "${CONTAINER_NAME}" > "${BACKUP_PATH}/container_state.json" || true
    docker logs "${CONTAINER_NAME}" &> "${BACKUP_PATH}/container_logs.txt" || true
fi

log_success "Backup created: ${BACKUP_PATH}"
echo ""

# Step 3: Validate secrets
log_info "Step 3/9: Validating production secrets..."

# Check for validation script (MUST exist for production deployment)
if [ -f "scripts/verify-deployment-secrets.sh" ]; then
    chmod +x scripts/verify-deployment-secrets.sh || error_exit "Failed to make validation script executable"
    ./scripts/verify-deployment-secrets.sh production || error_exit "Secrets validation failed - fix issues above"
    log_success "Secrets validation passed"
else
    error_exit "Secrets validation script not found: scripts/verify-deployment-secrets.sh (REQUIRED for production)"
fi
echo ""

# Step 4: Run security checks
log_info "Step 4/9: Running security checks..."

# Run npm audit
log_info "Checking for known vulnerabilities..."
npm audit --audit-level=high || log_warning "npm audit found potential issues"

# Run linting with security rules
if npm run lint &> /dev/null; then
    log_success "Linting passed"
else
    log_warning "Linting found issues, review before proceeding"
fi
echo ""

# Step 5: Build production image
log_info "Step 5/9: Building production Docker image..."
log_info "This may take a few minutes..."

docker-compose -f "${COMPOSE_FILE}" build --no-cache || error_exit "Docker build failed"

# Tag image with version
VERSION=$(date +%Y%m%d.%H%M%S)
docker tag "${IMAGE_NAME}" "agentic-base-integration:${VERSION}" || error_exit "Failed to tag image"

log_success "Docker image built: ${IMAGE_NAME}"
log_success "Version tag: ${VERSION}"
echo ""

# Step 6: Stop current production container
log_info "Step 6/9: Stopping current production container..."

if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_info "Gracefully stopping production container..."

    # Give container time to shut down gracefully
    docker-compose -f "${COMPOSE_FILE}" stop || error_exit "Failed to stop container"

    # Wait for graceful shutdown
    log_info "Waiting for graceful shutdown (max 30s)..."
    TIMEOUT=30
    ELAPSED=0
    while docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$" && [ ${ELAPSED} -lt ${TIMEOUT} ]; do
        sleep 1
        ELAPSED=$((ELAPSED + 1))
        echo -n "."
    done
    echo ""

    # Remove stopped container
    docker-compose -f "${COMPOSE_FILE}" down || error_exit "Failed to remove container"

    log_success "Production container stopped"
else
    log_info "No running production container found"
fi
echo ""

# Step 7: Start new production container
log_info "Step 7/9: Starting new production container..."

docker-compose -f "${COMPOSE_FILE}" up -d || error_exit "Failed to start container"

log_success "Container started: ${CONTAINER_NAME}"
echo ""

# Step 8: Wait for health check
log_info "Step 8/9: Waiting for service to become healthy..."

MAX_WAIT=90  # Longer wait for production
ELAPSED=0
INTERVAL=5

while [ ${ELAPSED} -lt ${MAX_WAIT} ]; do
    HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' "${CONTAINER_NAME}" 2>/dev/null || echo "unknown")

    if [ "${HEALTH_STATUS}" = "healthy" ]; then
        log_success "Service is healthy!"
        break
    elif [ "${HEALTH_STATUS}" = "unhealthy" ]; then
        log_error "Service health check failed"
        log_info "Showing recent logs:"
        docker-compose -f "${COMPOSE_FILE}" logs --tail=100

        # Automatic rollback
        log_warning "Attempting automatic rollback..."
        docker-compose -f "${COMPOSE_FILE}" down || true

        # Restore from backup
        if [ -d "${BACKUP_PATH}/data" ]; then
            log_info "Restoring data from backup..."
            rm -rf data
            cp -r "${BACKUP_PATH}/data" data || log_error "Failed to restore data"
        fi

        error_exit "Deployment failed: service unhealthy"
    elif [ "${HEALTH_STATUS}" = "starting" ] || [ "${HEALTH_STATUS}" = "unknown" ]; then
        echo -n "."
        sleep ${INTERVAL}
        ELAPSED=$((ELAPSED + INTERVAL))
    else
        error_exit "Unexpected health status: ${HEALTH_STATUS}"
    fi
done

if [ ${ELAPSED} -ge ${MAX_WAIT} ]; then
    log_error "Service did not become healthy within ${MAX_WAIT} seconds"
    log_info "Showing recent logs:"
    docker-compose -f "${COMPOSE_FILE}" logs --tail=100
    error_exit "Deployment failed: health check timeout"
fi
echo ""

# Step 9: Verify deployment
log_info "Step 9/9: Verifying production deployment..."

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    error_exit "Container is not running"
fi

# Check health endpoint
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/health || echo "000")
if [ "${HTTP_STATUS}" = "200" ]; then
    log_success "Health endpoint responding: HTTP ${HTTP_STATUS}"
else
    error_exit "Health endpoint not responding: HTTP ${HTTP_STATUS}"
fi

# Verify Discord connection (check logs for connection success)
log_info "Checking Discord connection..."
sleep 5
if docker logs "${CONTAINER_NAME}" 2>&1 | grep -q "Discord bot connected"; then
    log_success "Discord bot connected successfully"
else
    log_warning "Could not verify Discord connection from logs"
fi

# Show container status
log_info "Container status:"
docker ps --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""

# Show resource usage
log_info "Initial resource usage:"
docker stats "${CONTAINER_NAME}" --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"
echo ""

# Print success message
echo "========================================================================"
log_success "${BOLD}PRODUCTION DEPLOYMENT COMPLETED SUCCESSFULLY!${NC}"
echo "========================================================================"
echo ""
log_info "Deployment details:"
echo "  Container: ${CONTAINER_NAME}"
echo "  Image: ${IMAGE_NAME}"
echo "  Version: ${VERSION}"
echo "  Backup: ${BACKUP_PATH}"
echo ""
log_info "Endpoints:"
echo "  Health: http://localhost:3000/health"
echo "  Ready: http://localhost:3000/ready"
echo "  Metrics: http://localhost:3000/metrics"
echo ""
log_info "Monitoring commands:"
echo "  View logs:     docker-compose -f ${COMPOSE_FILE} logs -f"
echo "  Check health:  curl http://localhost:3000/health | jq ."
echo "  Check metrics: curl http://localhost:3000/metrics"
echo "  Container stats: docker stats ${CONTAINER_NAME}"
echo ""
log_warning "Post-deployment tasks:"
echo "  1. Monitor logs for the next 1 hour"
echo "  2. Verify Discord bot responds to commands"
echo "  3. Test webhook endpoints (Linear, GitHub, Vercel)"
echo "  4. Monitor error rates and response times"
echo "  5. Check alerting system receives metrics"
echo "  6. Notify stakeholders of successful deployment"
echo ""
log_info "If issues occur, rollback with:"
echo "  ./scripts/rollback-production.sh ${VERSION}"
echo ""
