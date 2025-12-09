#!/bin/bash
# ============================================================================
# Deploy Application Script
# ============================================================================
# Purpose: Deploy DevRel integration application code and configuration
# Usage: ./04-deploy-app.sh (run as devrel user, NOT root)
# Requirements: Run as application user (devrel), NOT with sudo
# ============================================================================

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
APP_DIR="/opt/devrel-integration"
REPO_URL="${REPO_URL:-https://github.com/your-org/agentic-base.git}"
BRANCH="${BRANCH:-main}"

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
error_exit() { log_error "$1"; exit 1; }

# Check NOT running as root
if [ "$EUID" -eq 0 ]; then
    error_exit "This script must NOT be run as root. Run as the devrel user."
fi

# Check running as correct user
CURRENT_USER=$(whoami)
if [ "$CURRENT_USER" != "devrel" ]; then
    log_warning "Current user: ${CURRENT_USER} (expected: devrel)"
    read -p "Continue anyway? (yes/no): " CONFIRM
    [ "$CONFIRM" = "yes" ] || exit 0
fi

echo "========================================================================"
echo "  Deploy Application - DevRel Integration"
echo "========================================================================"
echo ""
log_info "This script will:"
echo "  - Clone application repository (or update existing)"
echo "  - Install npm dependencies"
echo "  - Build TypeScript application"
echo "  - Set up environment configuration"
echo "  - Validate secrets"
echo ""
read -p "Continue? (yes/no): " CONFIRM
[ "$CONFIRM" = "yes" ] || exit 0
echo ""

# Step 1: Clone or update repository
log_info "Step 1/7: Fetching application code..."

if [ -d "${APP_DIR}/.git" ]; then
    log_info "Repository exists. Updating..."
    cd "${APP_DIR}" || error_exit "Failed to cd to ${APP_DIR}"

    # Fetch latest changes
    git fetch origin || error_exit "Failed to fetch from remote"

    # Show current branch and commit
    CURRENT_BRANCH=$(git branch --show-current)
    CURRENT_COMMIT=$(git rev-parse --short HEAD)
    log_info "Current: ${CURRENT_BRANCH} @ ${CURRENT_COMMIT}"

    # Pull latest changes
    git pull origin "${BRANCH}" || error_exit "Failed to pull latest changes"

    NEW_COMMIT=$(git rev-parse --short HEAD)
    if [ "$CURRENT_COMMIT" != "$NEW_COMMIT" ]; then
        log_success "Updated: ${CURRENT_COMMIT} → ${NEW_COMMIT}"
    else
        log_info "Already up to date"
    fi
else
    log_info "Cloning repository..."

    # Navigate to parent directory
    cd /opt || error_exit "Failed to cd to /opt"

    # Clone repository
    git clone -b "${BRANCH}" "${REPO_URL}" devrel-integration || error_exit "Failed to clone repository"

    cd "${APP_DIR}" || error_exit "Failed to cd to ${APP_DIR}"

    log_success "Repository cloned"
fi
echo ""

# Step 2: Navigate to integration directory
log_info "Step 2/7: Navigating to integration directory..."

if [ -d "${APP_DIR}/devrel-integration" ]; then
    cd "${APP_DIR}/devrel-integration" || error_exit "Failed to cd to devrel-integration"
    log_success "Using devrel-integration/ subdirectory"
else
    log_warning "devrel-integration/ subdirectory not found, assuming root is app directory"
fi
echo ""

# Step 3: Install dependencies
log_info "Step 3/7: Installing npm dependencies..."

if [ ! -f "package.json" ]; then
    error_exit "package.json not found. Are you in the correct directory?"
fi

# Clean install (removes node_modules and reinstalls)
log_info "Running npm ci (clean install)..."
npm ci --production=false || error_exit "Failed to install dependencies"

log_success "Dependencies installed"
echo ""

# Step 4: Build application
log_info "Step 4/7: Building TypeScript application..."

if [ -f "tsconfig.json" ]; then
    # Build TypeScript
    npm run build || error_exit "Build failed"

    # Verify build output
    if [ ! -d "dist" ] || [ ! -f "dist/bot.js" ]; then
        error_exit "Build succeeded but dist/bot.js not found"
    fi

    log_success "Application built successfully"
else
    log_warning "tsconfig.json not found, skipping build step"
fi
echo ""

# Step 5: Set up environment configuration
log_info "Step 5/7: Setting up environment configuration..."

# Check if secrets directory exists
if [ ! -d "secrets" ]; then
    mkdir -p secrets || error_exit "Failed to create secrets directory"
    log_info "Created secrets/ directory"
fi

# Check if .env.local.example exists
if [ ! -f "secrets/.env.local.example" ]; then
    error_exit "Template file not found: secrets/.env.local.example"
fi

# Check if .env.local exists
if [ ! -f "secrets/.env.local" ]; then
    log_warning "Environment file not found: secrets/.env.local"
    echo ""
    log_info "To create environment file:"
    echo "  1. cp secrets/.env.local.example secrets/.env.local"
    echo "  2. Edit secrets/.env.local and fill in real values"
    echo "  3. chmod 600 secrets/.env.local"
    echo ""
    read -p "Create environment file from template now? (yes/no): " CREATE_ENV
    if [ "$CREATE_ENV" = "yes" ]; then
        cp secrets/.env.local.example secrets/.env.local || error_exit "Failed to copy template"
        chmod 600 secrets/.env.local || error_exit "Failed to set permissions"
        log_success "Created secrets/.env.local from template"
        log_warning "IMPORTANT: Edit secrets/.env.local and replace all placeholder values!"
        log_warning "Run this script again after configuring secrets."
        exit 0
    else
        error_exit "Cannot proceed without environment configuration"
    fi
fi

# Verify permissions
PERMS=$(stat -c "%a" secrets/.env.local 2>/dev/null || stat -f "%A" secrets/.env.local 2>/dev/null)
if [ "$PERMS" != "600" ]; then
    log_warning "Environment file has insecure permissions: ${PERMS}"
    chmod 600 secrets/.env.local || error_exit "Failed to fix permissions"
    log_success "Fixed permissions: 600"
fi

log_success "Environment configuration ready"
echo ""

# Step 6: Validate secrets
log_info "Step 6/7: Validating secrets..."

if [ -f "scripts/verify-deployment-secrets.sh" ]; then
    chmod +x scripts/verify-deployment-secrets.sh || true
    ./scripts/verify-deployment-secrets.sh development || {
        log_error "Secrets validation failed!"
        log_error "Fix the issues above and run this script again."
        exit 1
    }
    log_success "Secrets validation passed"
else
    log_warning "Secrets validation script not found: scripts/verify-deployment-secrets.sh"
    log_warning "Skipping validation (NOT recommended for production)"
fi
echo ""

# Step 7: Set up PM2
log_info "Step 7/7: Setting up PM2 process manager..."

# Check if ecosystem.config.js exists
if [ ! -f "ecosystem.config.js" ]; then
    error_exit "PM2 config not found: ecosystem.config.js"
fi

# Check if PM2 is installed
if ! command -v pm2 &> /dev/null; then
    error_exit "PM2 not installed. Run: sudo ./03-install-dependencies.sh"
fi

# Stop existing PM2 process (if running)
if pm2 list | grep -q "agentic-base-bot"; then
    log_info "Stopping existing PM2 process..."
    pm2 stop agentic-base-bot || true
    pm2 delete agentic-base-bot || true
fi

# Start application with PM2
log_info "Starting application with PM2..."
pm2 start ecosystem.config.js --env production || error_exit "Failed to start application"

# Save PM2 process list
pm2 save || log_warning "Failed to save PM2 process list"

log_success "Application started with PM2"
echo ""

# Wait for application to start
log_info "Waiting for application to start (10 seconds)..."
sleep 10

# Check application status
echo "========================================================================"
log_success "Application deployed successfully!"
echo "========================================================================"
echo ""
log_info "Application status:"
pm2 list
echo ""
log_info "Recent logs:"
pm2 logs agentic-base-bot --lines 20 --nostream
echo ""
log_info "Useful commands:"
echo "  View logs:       pm2 logs agentic-base-bot"
echo "  Restart app:     pm2 restart agentic-base-bot"
echo "  Stop app:        pm2 stop agentic-base-bot"
echo "  Check status:    pm2 status"
echo "  Monitor:         pm2 monit"
echo ""
log_info "Health check:"
if curl -sf http://localhost:3000/health > /dev/null; then
    log_success "Health check passed: http://localhost:3000/health"
    curl -s http://localhost:3000/health | jq . || cat
else
    log_warning "Health check failed or not yet available"
    log_info "Check logs: pm2 logs agentic-base-bot"
fi
echo ""
log_info "Next steps:"
echo "  1. Monitor logs for any errors: pm2 logs agentic-base-bot"
echo "  2. Test Discord bot responds to commands"
echo "  3. Configure nginx reverse proxy: sudo ./06-setup-ssl.sh"
echo "  4. Set up monitoring: sudo ./05-setup-monitoring.sh (optional)"
echo ""
