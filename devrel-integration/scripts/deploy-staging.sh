#!/bin/bash
# ============================================================================
# Staging Deployment Script
# ============================================================================
# Purpose: Deploy agentic-base integration to staging environment
# Usage: ./scripts/deploy-staging.sh
# ============================================================================

set -euo pipefail  # Exit on error, undefined variable, or pipe failure

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="docker-compose.staging.yml"
IMAGE_NAME="agentic-base-integration:staging"
CONTAINER_NAME="agentic-base-bot-staging"

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
    exit 1
}

# Print header
echo "========================================================================"
echo "  Agentic-Base Integration - Staging Deployment"
echo "========================================================================"
echo ""

# Step 1: Pre-deployment checks
log_info "Step 1/7: Running pre-deployment checks..."

# Check if running from correct directory
cd "${PROJECT_DIR}" || error_exit "Failed to change to project directory"

# Check if Docker is installed and running
if ! command -v docker &> /dev/null; then
    error_exit "Docker is not installed. Please install Docker first."
fi

if ! docker info &> /dev/null; then
    error_exit "Docker daemon is not running. Please start Docker."
fi

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null; then
    error_exit "docker-compose is not installed. Please install docker-compose."
fi

# Check if staging secrets file exists
if [ ! -f "secrets/.env.staging" ]; then
    log_warning "Staging secrets file not found: secrets/.env.staging"
    log_info "Please create secrets/.env.staging with required environment variables."
    log_info "You can use secrets/.env.local.example as a template."
    error_exit "Missing staging secrets file"
fi

# Verify secrets file permissions
SECRETS_PERMS=$(stat -c "%a" secrets/.env.staging 2>/dev/null || stat -f "%A" secrets/.env.staging 2>/dev/null)
if [ "${SECRETS_PERMS}" != "600" ]; then
    log_warning "Secrets file has insecure permissions: ${SECRETS_PERMS}"
    log_info "Fixing permissions to 600 (read/write for owner only)..."
    chmod 600 secrets/.env.staging || error_exit "Failed to fix secrets permissions"
fi

log_success "Pre-deployment checks passed"
echo ""

# Step 2: Validate secrets
log_info "Step 2/7: Validating secrets configuration..."

# Check for validation script
if [ -f "scripts/verify-deployment-secrets.sh" ]; then
    chmod +x scripts/verify-deployment-secrets.sh || error_exit "Failed to make validation script executable"
    ./scripts/verify-deployment-secrets.sh staging || error_exit "Secrets validation failed - fix issues above"
    log_success "Secrets validation passed"
else
    log_warning "Secrets validation script not found: scripts/verify-deployment-secrets.sh"
    log_warning "Skipping validation (NOT recommended - consider creating the validation script)"
fi
echo ""

# Step 3: Build Docker image
log_info "Step 3/7: Building Docker image..."
log_info "This may take a few minutes on first build..."

docker-compose -f "${COMPOSE_FILE}" build --no-cache || error_exit "Docker build failed"

log_success "Docker image built successfully: ${IMAGE_NAME}"
echo ""

# Step 4: Stop existing container (if running)
log_info "Step 4/7: Stopping existing staging container..."

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_info "Found existing container, stopping and removing..."
    docker-compose -f "${COMPOSE_FILE}" down || error_exit "Failed to stop existing container"
    log_success "Existing container stopped and removed"
else
    log_info "No existing container found, proceeding with fresh deployment"
fi
echo ""

# Step 5: Start new container
log_info "Step 5/7: Starting staging container..."

docker-compose -f "${COMPOSE_FILE}" up -d || error_exit "Failed to start container"

log_success "Container started: ${CONTAINER_NAME}"
echo ""

# Step 6: Wait for health check
log_info "Step 6/7: Waiting for service to become healthy..."

MAX_WAIT=60  # Maximum wait time in seconds
ELAPSED=0
INTERVAL=5

while [ ${ELAPSED} -lt ${MAX_WAIT} ]; do
    # Check container health status
    HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' "${CONTAINER_NAME}" 2>/dev/null || echo "unknown")

    if [ "${HEALTH_STATUS}" = "healthy" ]; then
        log_success "Service is healthy!"
        break
    elif [ "${HEALTH_STATUS}" = "unhealthy" ]; then
        log_error "Service health check failed"
        log_info "Showing recent logs:"
        docker-compose -f "${COMPOSE_FILE}" logs --tail=50
        error_exit "Deployment failed: service unhealthy"
    elif [ "${HEALTH_STATUS}" = "starting" ] || [ "${HEALTH_STATUS}" = "unknown" ]; then
        echo -n "."
        sleep ${INTERVAL}
        ELAPSED=$((ELAPSED + INTERVAL))
    else
        log_error "Unexpected health status: ${HEALTH_STATUS}"
        error_exit "Deployment failed: unexpected health status"
    fi
done

if [ ${ELAPSED} -ge ${MAX_WAIT} ]; then
    log_error "Service did not become healthy within ${MAX_WAIT} seconds"
    log_info "Showing recent logs:"
    docker-compose -f "${COMPOSE_FILE}" logs --tail=50
    error_exit "Deployment failed: health check timeout"
fi
echo ""

# Step 7: Verify deployment
log_info "Step 7/7: Verifying deployment..."

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    error_exit "Container is not running"
fi

# Check health endpoint
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/health || echo "000")
if [ "${HTTP_STATUS}" = "200" ]; then
    log_success "Health endpoint responding: HTTP ${HTTP_STATUS}"
else
    log_error "Health endpoint not responding: HTTP ${HTTP_STATUS}"
    error_exit "Deployment verification failed"
fi

# Show container status
log_info "Container status:"
docker ps --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""

# Show resource usage
log_info "Resource usage:"
docker stats "${CONTAINER_NAME}" --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"
echo ""

# Print success message
echo "========================================================================"
log_success "Staging deployment completed successfully!"
echo "========================================================================"
echo ""
log_info "Container name: ${CONTAINER_NAME}"
log_info "Image: ${IMAGE_NAME}"
log_info "Health check: http://localhost:3000/health"
log_info "Metrics: http://localhost:3000/metrics"
echo ""
log_info "View logs:"
echo "  docker-compose -f ${COMPOSE_FILE} logs -f"
echo ""
log_info "Monitor health:"
echo "  watch 'docker ps --filter name=${CONTAINER_NAME}'"
echo "  watch 'curl -s http://localhost:3000/health | jq .'"
echo ""
log_info "Stop deployment:"
echo "  docker-compose -f ${COMPOSE_FILE} down"
echo ""
log_warning "Next steps:"
echo "  1. Monitor logs for errors: docker-compose -f ${COMPOSE_FILE} logs -f"
echo "  2. Run integration tests: npm run test:integration"
echo "  3. Verify Discord bot functionality"
echo "  4. Test webhook endpoints"
echo "  5. Validate Linear API integration"
echo ""
