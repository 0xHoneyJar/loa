# ============================================================================
# Multi-stage Production Dockerfile for Agentic-Base Integration
# ============================================================================
# Security Features:
# - SHA-256 pinned base images (supply chain protection)
# - Non-root user execution (privilege minimization)
# - Security updates applied (vulnerability patching)
# - Minimal attack surface (alpine base, production deps only)
# - Health check support (reliability monitoring)
# ============================================================================

# Stage 1: Builder - Compile TypeScript to JavaScript
FROM node:18-alpine@sha256:435dcad253bb5b7f347ebc69c8cc52de7c912eb7241098b920f2fc2d7843183d AS builder

WORKDIR /app

# Install build dependencies (Python, make, g++ for native modules)
RUN apk add --no-cache python3 make g++

# Copy dependency manifests first (Docker layer caching optimization)
COPY package*.json ./
COPY tsconfig.json ./

# Install ALL dependencies (including devDependencies for TypeScript compilation)
RUN npm ci --ignore-scripts

# Copy application source code
COPY src/ ./src/
COPY config/ ./config/

# Compile TypeScript to JavaScript
RUN npm run build

# Verify build output exists
RUN test -d dist || (echo "Build failed: dist/ directory not created" && exit 1)

# ============================================================================
# Stage 2: Production - Minimal runtime image
# ============================================================================
FROM node:18-alpine@sha256:435dcad253bb5b7f347ebc69c8cc52de7c912eb7241098b920f2fc2d7843183d AS production

# Apply security updates
RUN apk upgrade --no-cache && \
    apk add --no-cache dumb-init

# Create non-root user and group
RUN addgroup -g 1001 nodejs && \
    adduser -S -u 1001 -G nodejs nodejs

WORKDIR /app

# Copy dependency manifests
COPY package*.json ./

# Install ONLY production dependencies (no devDependencies)
RUN npm ci --only=production --ignore-scripts && \
    npm cache clean --force

# Copy compiled application from builder stage
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/config ./config

# Create required directories with secure permissions
RUN mkdir -p logs data && \
    chown -R nodejs:nodejs /app && \
    chmod 700 logs data

# Switch to non-root user (all subsequent commands run as 'nodejs')
USER nodejs

# Expose health check and webhook port
EXPOSE 3000

# Health check configuration
# - Interval: 30s (check every 30 seconds)
# - Timeout: 10s (fail if no response in 10 seconds)
# - Start period: 40s (grace period during startup)
# - Retries: 3 (mark unhealthy after 3 consecutive failures)
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/health', (res) => { \
    process.exit(res.statusCode === 200 ? 0 : 1); \
  }).on('error', () => { process.exit(1); });"

# Use dumb-init as PID 1 (proper signal handling for graceful shutdown)
ENTRYPOINT ["/usr/bin/dumb-init", "--"]

# Start the Discord bot
CMD ["node", "dist/bot.js"]
