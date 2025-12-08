#!/bin/bash
# ============================================================================
# Secrets Validation Script
# ============================================================================
# Purpose: Validate all required secrets are present and properly formatted
# Usage: ./scripts/verify-deployment-secrets.sh [environment]
# Arguments:
#   environment - Optional: local, staging, production (default: local)
# ============================================================================

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV="${1:-local}"
SECRETS_FILE="secrets/.env.${ENV}"

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

# Validation counters
ERRORS=0
WARNINGS=0
CHECKS=0

# Header
echo "========================================================================"
echo "  Secrets Validation - ${ENV} environment"
echo "========================================================================"
echo ""

# Change to project directory
cd "${PROJECT_DIR}" || exit 1

# Check if secrets file exists
if [ ! -f "${SECRETS_FILE}" ]; then
    log_error "Secrets file not found: ${SECRETS_FILE}"
    log_info "Create it using: cp secrets/.env.local.example ${SECRETS_FILE}"
    exit 1
fi

log_info "Validating secrets file: ${SECRETS_FILE}"
echo ""

# Check file permissions
log_info "Checking file permissions..."
PERMS=$(stat -c "%a" "${SECRETS_FILE}" 2>/dev/null || stat -f "%A" "${SECRETS_FILE}" 2>/dev/null)
CHECKS=$((CHECKS + 1))

if [ "${PERMS}" = "600" ]; then
    log_success "File permissions are secure: ${PERMS}"
elif [ "${PERMS}" = "400" ]; then
    log_success "File permissions are read-only: ${PERMS}"
else
    log_error "File permissions are insecure: ${PERMS} (should be 600)"
    log_info "Fix with: chmod 600 ${SECRETS_FILE}"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# Load secrets file
log_info "Loading secrets..."
set -a
# shellcheck disable=SC1090
source "${SECRETS_FILE}"
set +a
log_success "Secrets loaded"
echo ""

# Validation functions
check_required() {
    local NAME="$1"
    local VALUE="${!NAME:-}"
    CHECKS=$((CHECKS + 1))

    if [ -z "${VALUE}" ]; then
        log_error "${NAME} is not set"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
    log_success "${NAME} is set"
    return 0
}

check_format() {
    local NAME="$1"
    local VALUE="${!NAME:-}"
    local PATTERN="$2"
    local DESCRIPTION="$3"
    CHECKS=$((CHECKS + 1))

    if [ -z "${VALUE}" ]; then
        log_warning "${NAME} is empty, skipping format check"
        WARNINGS=$((WARNINGS + 1))
        return 1
    fi

    if [[ ! "${VALUE}" =~ ${PATTERN} ]]; then
        log_error "${NAME} format is invalid (${DESCRIPTION})"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
    log_success "${NAME} format is valid"
    return 0
}

check_not_example() {
    local NAME="$1"
    local VALUE="${!NAME:-}"
    CHECKS=$((CHECKS + 1))

    if [ -z "${VALUE}" ]; then
        return 0  # Already caught by check_required
    fi

    if [[ "${VALUE}" =~ (your_|example|changeme|test_|dummy) ]]; then
        log_error "${NAME} contains example/placeholder value"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
    log_success "${NAME} is not an example value"
    return 0
}

# Discord secrets validation
log_info "Validating Discord secrets..."
check_required "DISCORD_BOT_TOKEN"
if [ -n "${DISCORD_BOT_TOKEN:-}" ]; then
    check_format "DISCORD_BOT_TOKEN" "^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$" "Discord bot token (3 parts separated by dots)"
    check_not_example "DISCORD_BOT_TOKEN"
fi

check_required "DISCORD_GUILD_ID"
if [ -n "${DISCORD_GUILD_ID:-}" ]; then
    check_format "DISCORD_GUILD_ID" "^[0-9]+$" "Discord guild ID (numeric)"
    check_not_example "DISCORD_GUILD_ID"
fi
echo ""

# Linear secrets validation
log_info "Validating Linear secrets..."
check_required "LINEAR_API_KEY"
if [ -n "${LINEAR_API_KEY:-}" ]; then
    check_format "LINEAR_API_KEY" "^lin_api_[A-Za-z0-9]{40,}$" "Linear API key (starts with lin_api_)"
    check_not_example "LINEAR_API_KEY"
fi

check_required "LINEAR_TEAM_ID"
if [ -n "${LINEAR_TEAM_ID:-}" ]; then
    check_format "LINEAR_TEAM_ID" "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$" "Linear team ID (UUID format)"
    check_not_example "LINEAR_TEAM_ID"
fi

check_required "LINEAR_WEBHOOK_SECRET"
if [ -n "${LINEAR_WEBHOOK_SECRET:-}" ]; then
    check_not_example "LINEAR_WEBHOOK_SECRET"
    # Check minimum length
    if [ ${#LINEAR_WEBHOOK_SECRET} -lt 32 ]; then
        log_warning "LINEAR_WEBHOOK_SECRET is shorter than 32 characters (recommended: 64+)"
        WARNINGS=$((WARNINGS + 1))
    else
        log_success "LINEAR_WEBHOOK_SECRET length is adequate"
    fi
fi
echo ""

# Optional: GitHub secrets (only if GitHub integration is enabled)
if [ -n "${GITHUB_TOKEN:-}" ] || [ -n "${GITHUB_WEBHOOK_SECRET:-}" ]; then
    log_info "Validating GitHub secrets (optional)..."

    if [ -n "${GITHUB_TOKEN:-}" ]; then
        check_format "GITHUB_TOKEN" "^(ghp|gho|ghs|ghr)_[A-Za-z0-9]{36,}$" "GitHub token (starts with ghp_, gho_, ghs_, or ghr_)"
        check_not_example "GITHUB_TOKEN"
    fi

    if [ -n "${GITHUB_WEBHOOK_SECRET:-}" ]; then
        check_not_example "GITHUB_WEBHOOK_SECRET"
        if [ ${#GITHUB_WEBHOOK_SECRET} -lt 20 ]; then
            log_warning "GITHUB_WEBHOOK_SECRET is shorter than 20 characters"
            WARNINGS=$((WARNINGS + 1))
        fi
    fi
    echo ""
fi

# Optional: Vercel secrets (only if Vercel integration is enabled)
if [ -n "${VERCEL_TOKEN:-}" ] || [ -n "${VERCEL_WEBHOOK_SECRET:-}" ]; then
    log_info "Validating Vercel secrets (optional)..."

    if [ -n "${VERCEL_TOKEN:-}" ]; then
        check_not_example "VERCEL_TOKEN"
    fi

    if [ -n "${VERCEL_WEBHOOK_SECRET:-}" ]; then
        check_not_example "VERCEL_WEBHOOK_SECRET"
        if [ ${#VERCEL_WEBHOOK_SECRET} -lt 20 ]; then
            log_warning "VERCEL_WEBHOOK_SECRET is shorter than 20 characters"
            WARNINGS=$((WARNINGS + 1))
        fi
    fi
    echo ""
fi

# Application configuration validation
log_info "Validating application configuration..."

check_required "NODE_ENV"
if [ -n "${NODE_ENV:-}" ]; then
    CHECKS=$((CHECKS + 1))
    if [[ "${NODE_ENV}" =~ ^(development|staging|production)$ ]]; then
        log_success "NODE_ENV is valid: ${NODE_ENV}"

        # Validate NODE_ENV matches requested environment
        if [ "${ENV}" = "local" ] && [ "${NODE_ENV}" != "development" ]; then
            log_warning "NODE_ENV (${NODE_ENV}) doesn't match environment (${ENV})"
            WARNINGS=$((WARNINGS + 1))
        elif [ "${ENV}" = "staging" ] && [ "${NODE_ENV}" != "staging" ]; then
            log_warning "NODE_ENV (${NODE_ENV}) doesn't match environment (${ENV})"
            WARNINGS=$((WARNINGS + 1))
        elif [ "${ENV}" = "production" ] && [ "${NODE_ENV}" != "production" ]; then
            log_error "NODE_ENV (${NODE_ENV}) doesn't match environment (${ENV})"
            ERRORS=$((ERRORS + 1))
        fi
    else
        log_error "NODE_ENV has invalid value: ${NODE_ENV}"
        ERRORS=$((ERRORS + 1))
    fi
fi

if [ -n "${LOG_LEVEL:-}" ]; then
    CHECKS=$((CHECKS + 1))
    if [[ "${LOG_LEVEL}" =~ ^(error|warn|info|http|verbose|debug|silly)$ ]]; then
        log_success "LOG_LEVEL is valid: ${LOG_LEVEL}"
    else
        log_warning "LOG_LEVEL has unusual value: ${LOG_LEVEL}"
        WARNINGS=$((WARNINGS + 1))
    fi
fi

if [ -n "${PORT:-}" ]; then
    CHECKS=$((CHECKS + 1))
    if [[ "${PORT}" =~ ^[0-9]+$ ]] && [ "${PORT}" -ge 1024 ] && [ "${PORT}" -le 65535 ]; then
        log_success "PORT is valid: ${PORT}"
    else
        log_error "PORT is invalid: ${PORT} (must be 1024-65535)"
        ERRORS=$((ERRORS + 1))
    fi
fi
echo ""

# Security checks
log_info "Running security checks..."

# Check for secrets in git history (if in git repo)
if [ -d .git ]; then
    CHECKS=$((CHECKS + 1))
    if git ls-files --error-unmatch "${SECRETS_FILE}" &> /dev/null; then
        log_error "Secrets file is tracked by git! This is a security risk!"
        log_info "Remove with: git rm --cached ${SECRETS_FILE}"
        ERRORS=$((ERRORS + 1))
    else
        log_success "Secrets file is not tracked by git"
    fi
fi

# Check .gitignore contains secrets pattern
if [ -f .gitignore ]; then
    CHECKS=$((CHECKS + 1))
    if grep -q "^secrets/" .gitignore || grep -q "\.env" .gitignore; then
        log_success ".gitignore properly excludes secrets"
    else
        log_warning ".gitignore may not exclude secrets files"
        WARNINGS=$((WARNINGS + 1))
    fi
fi
echo ""

# Print summary
echo "========================================================================"
echo "  Validation Summary"
echo "========================================================================"
echo ""
echo "Total checks: ${CHECKS}"
echo -e "${GREEN}Passed:${NC} $((CHECKS - ERRORS - WARNINGS))"
echo -e "${YELLOW}Warnings:${NC} ${WARNINGS}"
echo -e "${RED}Errors:${NC} ${ERRORS}"
echo ""

if [ ${ERRORS} -eq 0 ] && [ ${WARNINGS} -eq 0 ]; then
    log_success "All secrets validation checks passed!"
    echo ""
    exit 0
elif [ ${ERRORS} -eq 0 ]; then
    log_warning "${WARNINGS} warning(s) found, but no errors"
    log_info "Review warnings above and consider fixing them"
    echo ""
    exit 0
else
    log_error "${ERRORS} error(s) found!"
    log_info "Fix the errors above before deploying"
    echo ""
    exit 1
fi
