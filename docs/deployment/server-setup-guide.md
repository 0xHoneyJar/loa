# Server Setup Guide

This guide documents how to set up a bare metal or VPS server for running the DevRel integration application.

## Overview

The DevRel integration consists of:
- **Discord Bot**: Handles team communication, feedback capture, and commands
- **Webhook Server**: Receives events from Linear, GitHub, and Vercel
- **Cron Jobs**: Daily digests, scheduled sync tasks
- **Integration Services**: Connect organizational tools seamlessly

## Prerequisites

### Server Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| CPU | 1 vCPU | 2 vCPU |
| RAM | 1 GB | 2 GB |
| Storage | 20 GB SSD | 40 GB SSD |
| Network | 100 Mbps | 1 Gbps |
| OS | Debian 11+ / Ubuntu 20.04+ | Debian 12 / Ubuntu 22.04 |

### Access Requirements

- SSH access to the server (root or sudo-capable user)
- Server IP address
- SSH key pair (recommended) or password

### API Tokens (gather before setup)

- [ ] Discord Bot Token (from Discord Developer Portal)
- [ ] Linear API Key (from Linear Settings > API)
- [ ] GitHub Personal Access Token (optional, for webhook verification)
- [ ] Domain name (optional, for HTTPS)

## Quick Start

```bash
# 1. Run the setup command in Claude Code
/setup-server

# 2. Answer the agent's questions about your server
# 3. Review and copy the generated scripts
# 4. Execute scripts on your server in order:

ssh user@your-server-ip
sudo ./01-initial-setup.sh
sudo ./02-security-hardening.sh
sudo ./03-install-dependencies.sh
sudo ./04-deploy-app.sh

# 5. Verify deployment
pm2 status
curl http://localhost:3000/health
```

## Setup Scripts

The `/setup-server` command generates these scripts in `docs/deployment/scripts/`:

### 01-initial-setup.sh

Initial server configuration:
- System package updates
- Essential tools installation (curl, git, jq, htop)
- Deployment user creation
- Timezone and locale configuration
- Hostname setup

### 02-security-hardening.sh

Security configuration:
- UFW firewall setup
- fail2ban for SSH protection
- Automatic security updates
- SSH hardening (key-only auth, disable root login)
- Audit logging

### 03-install-dependencies.sh

Application dependencies:
- Node.js LTS installation
- PM2 process manager
- Optional: Docker, nginx, certbot

### 04-deploy-app.sh

Application deployment:
- Code deployment to `/opt/devrel-integration`
- npm dependencies installation
- TypeScript build
- Environment configuration
- PM2 service setup
- Log rotation configuration

### 05-setup-monitoring.sh (optional)

Monitoring stack:
- Prometheus node exporter
- Application metrics
- Grafana dashboards
- Alert configuration

### 06-setup-ssl.sh (optional)

SSL/HTTPS setup:
- nginx reverse proxy
- Let's Encrypt certificates
- Auto-renewal configuration

## Manual Setup Steps

If you prefer manual setup over scripts:

### 1. Initial Server Setup

```bash
# Update system
apt update && apt upgrade -y

# Install essentials
apt install -y curl git jq htop unzip

# Create deployment user
useradd -m -s /bin/bash devrel
usermod -aG sudo devrel

# Set timezone
timedatectl set-timezone UTC
```

### 2. Security Hardening

```bash
# Install and configure UFW
apt install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 443/tcp  # HTTPS
ufw allow 3000/tcp # App (if no nginx)
ufw --force enable

# Install fail2ban
apt install -y fail2ban
systemctl enable fail2ban
systemctl start fail2ban

# Harden SSH (edit /etc/ssh/sshd_config)
# PermitRootLogin no
# PasswordAuthentication no
# PubkeyAuthentication yes
systemctl restart sshd

# Enable automatic security updates
apt install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades
```

### 3. Install Node.js and PM2

```bash
# Install Node.js 20 LTS
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# Verify installation
node --version  # Should show v20.x.x
npm --version

# Install PM2 globally
npm install -g pm2

# Configure PM2 startup
pm2 startup systemd -u devrel --hp /home/devrel
```

### 4. Deploy Application

```bash
# Create application directory
mkdir -p /opt/devrel-integration
chown devrel:devrel /opt/devrel-integration

# Clone or copy application code
su - devrel
cd /opt/devrel-integration
git clone <your-repo> .
# Or copy files manually

# Install dependencies
npm ci --production

# Build TypeScript
npm run build

# Create secrets file
cp secrets/.env.local.example secrets/.env.local
nano secrets/.env.local  # Add your tokens

# Start with PM2
pm2 start ecosystem.config.js
pm2 save
```

### 5. Verify Deployment

```bash
# Check PM2 status
pm2 status

# Check application logs
pm2 logs devrel-bot

# Test health endpoint
curl http://localhost:3000/health

# Verify Discord connection (check logs)
pm2 logs devrel-bot --lines 50 | grep "Discord"
```

## Configuration Files

### PM2 Ecosystem (ecosystem.config.js)

```javascript
module.exports = {
  apps: [{
    name: 'devrel-bot',
    script: 'dist/bot.js',
    cwd: '/opt/devrel-integration',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '500M',
    env: {
      NODE_ENV: 'production'
    },
    error_file: '/var/log/devrel/error.log',
    out_file: '/var/log/devrel/out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z'
  }]
};
```

### Systemd Service (alternative to PM2)

```ini
[Unit]
Description=DevRel Integration Bot
After=network.target

[Service]
Type=simple
User=devrel
Group=devrel
WorkingDirectory=/opt/devrel-integration
EnvironmentFile=/opt/devrel-integration/secrets/.env.local
ExecStart=/usr/bin/node dist/bot.js
Restart=on-failure
RestartSec=10
StandardOutput=append:/var/log/devrel/out.log
StandardError=append:/var/log/devrel/error.log

[Install]
WantedBy=multi-user.target
```

### Nginx Configuration (for HTTPS)

```nginx
server {
    listen 80;
    server_name your-domain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name your-domain.com;

    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    location /webhooks/ {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /health {
        proxy_pass http://127.0.0.1:3000;
    }
}
```

## Directory Structure

After setup, your server will have:

```
/opt/devrel-integration/
├── dist/                    # Compiled JavaScript
├── config/                  # Configuration files
├── secrets/                 # API tokens (.env.local)
├── node_modules/            # Dependencies
├── ecosystem.config.js      # PM2 configuration
└── package.json

/var/log/devrel/
├── out.log                  # Application stdout
├── error.log                # Application stderr
└── *.log.gz                 # Rotated logs

/etc/systemd/system/
└── devrel-integration.service  # (if using systemd)

/etc/nginx/sites-available/
└── devrel-integration.conf     # (if using nginx)
```

## Troubleshooting

### Bot won't start

```bash
# Check PM2 status and logs
pm2 status
pm2 logs devrel-bot --lines 100

# Check if port is in use
lsof -i :3000

# Verify environment variables
cat /opt/devrel-integration/secrets/.env.local

# Test Discord token
curl -H "Authorization: Bot YOUR_TOKEN" \
  https://discord.com/api/users/@me
```

### Connection issues

```bash
# Check firewall
ufw status

# Check if application is listening
netstat -tlnp | grep 3000

# Check DNS resolution (if using domain)
dig your-domain.com
```

### Permission issues

```bash
# Fix ownership
chown -R devrel:devrel /opt/devrel-integration

# Fix log directory
mkdir -p /var/log/devrel
chown devrel:devrel /var/log/devrel
```

### Memory issues

```bash
# Check memory usage
free -h
pm2 monit

# Increase swap if needed
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

## Maintenance

### Regular Tasks

| Frequency | Task | Command |
|-----------|------|---------|
| Daily | Check logs for errors | `pm2 logs --lines 50` |
| Weekly | Review system resources | `htop`, `df -h` |
| Monthly | Update dependencies | `npm outdated && npm update` |
| Quarterly | Rotate API tokens | See secrets-rotation.md |

### Updates

```bash
# Pull latest code
cd /opt/devrel-integration
git pull

# Install dependencies and rebuild
npm ci --production
npm run build

# Restart application
pm2 restart devrel-bot
```

### Backups

```bash
# Backup configuration
tar -czf backup-config-$(date +%Y%m%d).tar.gz \
  /opt/devrel-integration/config \
  /opt/devrel-integration/secrets

# Store backup securely (encrypt if containing secrets)
gpg -c backup-config-$(date +%Y%m%d).tar.gz
```

## Security Checklist

- [ ] SSH key-only authentication enabled
- [ ] Root login disabled
- [ ] UFW firewall active with minimal ports
- [ ] fail2ban protecting SSH
- [ ] Automatic security updates enabled
- [ ] Application running as non-root user
- [ ] Secrets stored in .env.local (not in code)
- [ ] Log rotation configured
- [ ] SSL/TLS enabled (if using domain)

## Next Steps

After successful setup:

1. **Test Discord Bot**: Send `/show-sprint` command in your Discord server
2. **Configure Webhooks**: Set up Linear/GitHub webhooks pointing to your server
3. **Monitor**: Check logs regularly for the first few days
4. **Document**: Record any custom configurations made

## Related Documentation

- [Operational Runbook](runbooks/server-operations.md)
- [Security Checklist](security-checklist.md)
- [Verification Checklist](verification-checklist.md)
- [Quick Reference](quick-reference.md)

---

**Generated by**: `/setup-server` command
**Last Updated**: 2025-12-09
