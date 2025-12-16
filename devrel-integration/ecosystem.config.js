/**
 * PM2 Ecosystem Configuration for Onomancer Bot
 *
 * This configuration file defines how PM2 should manage the Onomancer Bot.
 *
 * Usage:
 *   Start:    pm2 start ecosystem.config.js --env production
 *   Stop:     pm2 stop onomancer-bot
 *   Restart:  pm2 restart onomancer-bot
 *   Reload:   pm2 reload onomancer-bot (zero-downtime)
 *   Logs:     pm2 logs onomancer-bot
 *   Monitor:  pm2 monit
 *   Status:   pm2 status
 *
 * Environment Variables:
 *   APP_DIR     - Application directory (default: /opt/devrel-integration)
 *   LOG_DIR     - Log directory (default: /var/log/devrel)
 *   SECRETS_DIR - Secrets directory (default: $APP_DIR/secrets)
 *   DATA_DIR    - Data directory (default: $APP_DIR/data)
 */

const path = require('path');

// Environment detection
const isProd = process.env.NODE_ENV === 'production';

// Directory configuration
const APP_DIR = process.env.APP_DIR || (isProd ? '/opt/devrel-integration' : __dirname);
const LOG_DIR = process.env.LOG_DIR || (isProd ? '/var/log/devrel' : path.join(__dirname, 'logs'));
const SECRETS_DIR = process.env.SECRETS_DIR || path.join(APP_DIR, 'secrets');
const DATA_DIR = process.env.DATA_DIR || path.join(APP_DIR, 'data');

module.exports = {
  apps: [
    {
      // Application identity
      name: 'onomancer-bot',
      script: 'dist/bot.js',
      cwd: APP_DIR,

      // Instance configuration
      // Discord bots must run single instance (WebSocket doesn't support multiple)
      instances: 1,
      exec_mode: 'fork',

      // Restart behavior
      autorestart: true,
      watch: false,
      max_memory_restart: '1G',

      // Environment variables file
      env_file: path.join(SECRETS_DIR, '.env.local'),

      // Development environment
      env: {
        NODE_ENV: 'development',
        LOG_LEVEL: 'debug',
        LOG_DIR: path.join(__dirname, 'logs'),
        DATA_DIR: path.join(__dirname, 'data'),
        SECRETS_DIR: path.join(__dirname, 'secrets'),
      },

      // Production environment
      env_production: {
        NODE_ENV: 'production',
        LOG_LEVEL: 'info',
        LOG_DIR: LOG_DIR,
        DATA_DIR: DATA_DIR,
        SECRETS_DIR: SECRETS_DIR,
        NODE_OPTIONS: '--max-old-space-size=1024 --enable-source-maps',
      },

      // Log configuration
      error_file: path.join(LOG_DIR, 'onomancer-error.log'),
      out_file: path.join(LOG_DIR, 'onomancer-out.log'),
      log_file: path.join(LOG_DIR, 'onomancer-combined.log'),
      log_date_format: 'YYYY-MM-DD HH:mm:ss.SSS Z',
      merge_logs: true,
      time: true,

      // Graceful shutdown
      kill_timeout: 10000,          // 10 seconds to shutdown gracefully
      wait_ready: true,             // Wait for process.send('ready')
      listen_timeout: 15000,        // 15 seconds to start

      // Restart strategy with exponential backoff
      restart_delay: 5000,          // Initial delay: 5 seconds
      exp_backoff_restart_delay: 1000,  // Exponential backoff base: 1s
      max_restarts: 10,             // Max restarts in min_uptime window
      min_uptime: '30s',            // Stable if running > 30s

      // Advanced options
      source_map_support: true,
      shutdown_with_message: true,
      instance_var: 'INSTANCE_ID',
      treekill: true,

      // Post-update commands (for pm2 deploy)
      post_update: ['npm ci', 'npm run build'],

      // Node.js arguments
      node_args: ['--enable-source-maps'],

      // Interpreter
      interpreter: 'node',
    },
  ],

  /**
   * Deployment configuration for PM2 deploy
   *
   * Usage:
   *   Setup:  pm2 deploy production setup
   *   Deploy: pm2 deploy production
   *   Update: pm2 deploy production update
   */
  deploy: {
    production: {
      // SSH configuration
      user: 'devrel',
      host: ['your-server-ip'],  // Replace with actual server IP
      ref: 'origin/main',
      repo: 'git@github.com:your-org/agentic-base.git',  // Replace with actual repo
      path: '/opt/devrel-integration',

      // Pre-setup commands (run once during setup)
      'pre-setup': [
        'mkdir -p /opt/devrel-integration/secrets',
        'mkdir -p /opt/devrel-integration/data',
        'mkdir -p /var/log/devrel',
      ].join(' && '),

      // Post-setup commands
      'post-setup': 'cd devrel-integration && npm ci --production=false',

      // Pre-deploy commands (on local machine)
      'pre-deploy-local': 'echo "Deploying Onomancer Bot to production..."',

      // Post-deploy commands (on server)
      'post-deploy': [
        'cd devrel-integration',
        'npm ci --production=false',
        'npm run build',
        'PM2_HOME=/opt/devrel-integration/.pm2 pm2 reload ecosystem.config.js --env production',
        'PM2_HOME=/opt/devrel-integration/.pm2 pm2 save',
      ].join(' && '),

      // SSH options
      ssh_options: 'ForwardAgent=yes',

      // Environment variables
      env: {
        NODE_ENV: 'production',
      },
    },

    staging: {
      user: 'devrel',
      host: ['staging-server-ip'],  // Replace with staging server IP
      ref: 'origin/develop',
      repo: 'git@github.com:your-org/agentic-base.git',
      path: '/opt/devrel-integration-staging',

      'post-deploy': [
        'cd devrel-integration',
        'npm ci --production=false',
        'npm run build',
        'pm2 reload ecosystem.config.js --env staging',
      ].join(' && '),

      env: {
        NODE_ENV: 'staging',
      },
    },
  },
};
