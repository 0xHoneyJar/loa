#!/bin/bash
#
# Onomancer Bot - Deployment Script
#
# This script deploys the Onomancer Bot application to the server.
# Run as the devrel user from the application directory.
#
# Usage: ./deploy.sh [OPTIONS]
#
# Options:
#   --build-only     Only build, don't restart services
#   --no-backup      Skip database backup before deployment
#   --force          Force deployment even if validation fails
#   --version TAG    Deploy specific git tag/branch (default: current)
#   --help           Show this help message
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default configuration
APP_DIR="/opt/devrel-integration"
SECRETS_DIR="$APP_DIR/secrets"
DATA_DIR="$APP_DIR/data"
BACKUP_DIR="$APP_DIR/backups"
LOG_DIR="/var/log/devrel"
PM2_HOME="$APP_DIR/.pm2"

BUILD_ONLY=false
NO_BACKUP=false
FORCE=false
VERSION=""

# Export PM2_HOME
export PM2_HOME

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
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

show_help() {
    head -19 "$0" | tail -14
    exit 0
}

# Validate environment
validate_environment() {
    log_step "Validating environment..."

    local errors=0

    # Check we're in the right directory
    if [[ ! -f "package.json" ]]; then
        log_error "package.json not found. Are you in the application directory?"
        ((errors++))
    fi

    # Check secrets file exists
    if [[ ! -f "$SECRETS_DIR/.env.local" ]]; then
        log_error "Secrets file not found: $SECRETS_DIR/.env.local"
        ((errors++))
    fi

    # Check required environment variables
    if [[ -f "$SECRETS_DIR/.env.local" ]]; then
        source "$SECRETS_DIR/.env.local"

        if [[ -z "${DISCORD_TOKEN:-}" ]]; then
            log_error "DISCORD_TOKEN not set in .env.local"
            ((errors++))
        fi

        if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
            log_warn "ANTHROPIC_API_KEY not set (transformations will fail)"
        fi

        if [[ -z "${GOOGLE_SERVICE_ACCOUNT_KEY_PATH:-}" ]] && [[ -z "${GOOGLE_SERVICE_ACCOUNT_KEY_JSON:-}" ]]; then
            log_warn "Google service account not configured (Google Docs will fail)"
        fi
    fi

    # Check node and npm
    if ! command -v node &> /dev/null; then
        log_error "Node.js not found"
        ((errors++))
    fi

    if ! command -v npm &> /dev/null; then
        log_error "npm not found"
        ((errors++))
    fi

    # Check PM2
    if ! command -v pm2 &> /dev/null; then
        log_error "PM2 not found. Install with: npm install -g pm2"
        ((errors++))
    fi

    if [[ $errors -gt 0 ]] && [[ "$FORCE" = false ]]; then
        log_error "Validation failed with $errors error(s). Use --force to override."
        exit 1
    fi

    log_success "Environment validated"
}

# Create database backup
backup_database() {
    if [[ "$NO_BACKUP" = true ]]; then
        log_info "Skipping database backup (--no-backup)"
        return
    fi

    log_step "Backing up database..."

    local db_file="$DATA_DIR/onomancer.db"

    if [[ -f "$db_file" ]]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_file="$BACKUP_DIR/onomancer_${timestamp}.db"

        mkdir -p "$BACKUP_DIR"
        cp "$db_file" "$backup_file"

        # Keep only last 7 backups
        ls -t "$BACKUP_DIR"/onomancer_*.db 2>/dev/null | tail -n +8 | xargs -r rm

        log_success "Database backed up to: $backup_file"
    else
        log_info "No existing database to backup"
    fi
}

# Pull latest code (if using git)
pull_code() {
    if [[ -d ".git" ]]; then
        log_step "Pulling latest code..."

        if [[ -n "$VERSION" ]]; then
            git fetch --all --tags
            git checkout "$VERSION"
            log_info "Checked out version: $VERSION"
        else
            git pull
        fi

        log_success "Code updated"
    else
        log_info "Not a git repository, skipping pull"
    fi
}

# Install dependencies
install_dependencies() {
    log_step "Installing dependencies..."

    # Use npm ci for clean installs (faster, more reliable)
    if [[ -f "package-lock.json" ]]; then
        npm ci --production=false
    else
        npm install
    fi

    log_success "Dependencies installed"
}

# Build application
build_application() {
    log_step "Building application..."

    # Run TypeScript compilation
    npm run build

    # Verify build output
    if [[ ! -f "dist/bot.js" ]]; then
        log_error "Build failed: dist/bot.js not found"
        exit 1
    fi

    # Ensure schema.sql is copied
    if [[ -f "src/database/schema.sql" ]] && [[ ! -f "dist/database/schema.sql" ]]; then
        mkdir -p dist/database
        cp src/database/schema.sql dist/database/
    fi

    log_success "Application built"
}

# Run tests (optional)
run_tests() {
    log_step "Running tests..."

    if npm run test --if-present 2>/dev/null; then
        log_success "Tests passed"
    else
        log_warn "Tests failed or not configured"
    fi
}

# Create/update PM2 ecosystem config
create_pm2_config() {
    log_step "Creating PM2 configuration..."

    cat > "$APP_DIR/ecosystem.config.js" << EOF
module.exports = {
  apps: [{
    name: 'onomancer-bot',
    script: 'dist/bot.js',
    cwd: '$APP_DIR',
    instances: 1,  // Discord bot should run single instance
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    env_file: '$SECRETS_DIR/.env.local',
    env: {
      NODE_ENV: 'production',
      LOG_LEVEL: 'info',
      LOG_DIR: '$LOG_DIR',
      DATA_DIR: '$DATA_DIR'
    },
    error_file: '$LOG_DIR/onomancer-error.log',
    out_file: '$LOG_DIR/onomancer-out.log',
    log_file: '$LOG_DIR/onomancer-combined.log',
    time: true,
    merge_logs: true,
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    // Graceful shutdown
    kill_timeout: 5000,
    wait_ready: true,
    listen_timeout: 10000,
    // Restart strategies
    exp_backoff_restart_delay: 1000,
    max_restarts: 10,
    min_uptime: 5000
  }]
};
EOF

    log_success "PM2 configuration created"
}

# Start/restart application with PM2
start_application() {
    if [[ "$BUILD_ONLY" = true ]]; then
        log_info "Build only mode, skipping application start"
        return
    fi

    log_step "Starting application with PM2..."

    # Check if app is already running
    if pm2 list | grep -q "onomancer-bot"; then
        log_info "Reloading existing application..."
        pm2 reload ecosystem.config.js --update-env
    else
        log_info "Starting new application..."
        pm2 start ecosystem.config.js
    fi

    # Wait for app to start
    sleep 3

    # Check status
    if pm2 list | grep -q "online.*onomancer-bot"; then
        log_success "Application started successfully"
    else
        log_error "Application failed to start"
        pm2 logs onomancer-bot --lines 20
        exit 1
    fi

    # Save PM2 process list
    pm2 save

    log_success "Application deployment complete"
}

# Verify deployment
verify_deployment() {
    log_step "Verifying deployment..."

    # Check PM2 status
    echo ""
    pm2 status
    echo ""

    # Check application logs for errors
    local errors=$(pm2 logs onomancer-bot --lines 10 --nostream 2>&1 | grep -c "error" || true)

    if [[ $errors -gt 0 ]]; then
        log_warn "Found $errors error(s) in recent logs"
        log_info "Check logs with: pm2 logs onomancer-bot"
    else
        log_success "No errors in recent logs"
    fi

    # Print deployment info
    echo ""
    echo "========================================"
    echo "  Deployment Summary"
    echo "========================================"
    echo ""
    echo "  Application: onomancer-bot"
    echo "  Directory:   $APP_DIR"
    echo "  PM2 Home:    $PM2_HOME"
    echo "  Logs:        $LOG_DIR"
    echo ""
    echo "Useful commands:"
    echo "  pm2 status              # Check status"
    echo "  pm2 logs onomancer-bot  # View logs"
    echo "  pm2 restart onomancer-bot"
    echo "  pm2 stop onomancer-bot"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --build-only)
            BUILD_ONLY=true
            shift
            ;;
        --no-backup)
            NO_BACKUP=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --help)
            show_help
            ;;
        *)
            log_error "Unknown option: $1. Use --help for usage."
            exit 1
            ;;
    esac
done

# Main deployment process
main() {
    echo ""
    echo "========================================"
    echo "  Onomancer Bot Deployment"
    echo "========================================"
    echo ""
    echo "  Time: $(date)"
    echo "  User: $(whoami)"
    echo "  Directory: $(pwd)"
    echo ""

    # Change to app directory
    cd "$APP_DIR"

    # Execute deployment steps
    validate_environment
    backup_database
    pull_code
    install_dependencies
    build_application
    create_pm2_config
    start_application
    verify_deployment

    log_success "Deployment completed successfully!"
}

# Run main function
main
