/**
 * PM2 Ecosystem Configuration
 *
 * This configuration file defines how PM2 should manage the agentic-base integration bot.
 *
 * Usage:
 *   Start: pm2 start ecosystem.config.js
 *   Stop: pm2 stop agentic-base-bot
 *   Restart: pm2 restart agentic-base-bot
 *   Logs: pm2 logs agentic-base-bot
 *   Monitor: pm2 monit
 */

module.exports = {
  apps: [
    {
      // Application name
      name: 'agentic-base-bot',

      // Script to run
      script: 'dist/bot.js',

      // Working directory (configurable via environment variable)
      cwd: process.env.APP_DIR || '/opt/devrel-integration',

      // Instances (1 = single instance, 0 or 'max' = use all CPU cores)
      instances: 1,

      // Execution mode ('fork' or 'cluster')
      exec_mode: 'fork',

      // Auto-restart on crash
      autorestart: true,

      // Watch for file changes (disable in production)
      watch: false,

      // Maximum memory before restart (500MB)
      max_memory_restart: '500M',

      // Environment variables
      env: {
        NODE_ENV: 'development',
      },

      env_production: {
        NODE_ENV: 'production',
      },

      // Load environment variables from file
      env_file: './secrets/.env.local',

      // Error log file
      error_file: './logs/pm2-error.log',

      // Output log file
      out_file: './logs/pm2-out.log',

      // Combined log file
      log_file: './logs/pm2-combined.log',

      // Log date format
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',

      // Merge logs from all instances
      merge_logs: true,

      // Time to wait before restart on crash (milliseconds) - TUNED
      restart_delay: 10000,  // 10 seconds (increased from 5s)

      // Maximum number of restart retries - TUNED
      max_restarts: 5,  // Reduced from 10 to prevent crash loops

      // Minimum uptime before restart is considered stable - TUNED
      min_uptime: '30s',  // Increased from 10s to better detect stable starts

      // Listen timeout (milliseconds)
      listen_timeout: 10000,

      // Kill timeout (milliseconds)
      kill_timeout: 5000,

      // Shutdown with SIGINT instead of SIGKILL
      shutdown_with_message: true,

      // Instance variables
      instance_var: 'INSTANCE_ID',

      // Source map support
      source_map_support: true,

      // Disable automatic ID increment
      increment_var: 'PORT',

      // Post-update command (run after PM2 updates)
      post_update: ['npm install', 'npm run build'],

      // Advanced features - Exponential backoff restart delay
      exp_backoff_restart_delay: 100,  // 100ms base (100, 200, 400, 800, 1600ms)

      // Monitoring
      // Uncomment to enable PM2 monitoring
      // pmx: true,
    },
  ],

  /**
   * Deployment configuration
   *
   * Uncomment and configure for PM2 deploy functionality
   */
  /*
  deploy: {
    production: {
      user: 'deploy',
      host: 'your-server.com',
      ref: 'origin/main',
      repo: 'git@github.com:your-org/agentic-base.git',
      path: '/opt/agentic-base',
      'pre-deploy-local': '',
      'post-deploy': 'cd integration && npm install && npm run build && pm2 reload ecosystem.config.js --env production',
      'pre-setup': '',
      'ssh_options': 'ForwardAgent=yes'
    },
    staging: {
      user: 'deploy',
      host: 'staging-server.com',
      ref: 'origin/develop',
      repo: 'git@github.com:your-org/agentic-base.git',
      path: '/opt/agentic-base-staging',
      'post-deploy': 'cd integration && npm install && npm run build && pm2 reload ecosystem.config.js --env staging',
      'ssh_options': 'ForwardAgent=yes'
    }
  }
  */
};
