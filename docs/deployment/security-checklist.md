# Security Checklist

Security verification checklist for DevRel server deployment.

## Pre-Deployment Checklist

### Server Access
- [ ] SSH key authentication configured
- [ ] Password authentication disabled in sshd_config
- [ ] Root login disabled
- [ ] SSH port changed from 22 (optional but recommended)
- [ ] Only necessary users have SSH access

### Firewall
- [ ] UFW installed and enabled
- [ ] Default deny incoming policy
- [ ] Only required ports open:
  - [ ] SSH (22 or custom)
  - [ ] HTTPS (443) - if using domain
  - [ ] HTTP (80) - only for Let's Encrypt redirect
  - [ ] App port (3000) - only if no nginx proxy
- [ ] No unnecessary services exposed

### Intrusion Prevention
- [ ] fail2ban installed and running
- [ ] fail2ban SSH jail configured
- [ ] Ban time and retry limits appropriate
- [ ] fail2ban logs being monitored

### System Updates
- [ ] System packages fully updated
- [ ] Automatic security updates enabled (unattended-upgrades)
- [ ] Update notification configured

## Application Security

### Secrets Management
- [ ] All secrets in `.env.local` file
- [ ] `.env.local` not committed to git
- [ ] Secrets file permissions restricted (600)
- [ ] No secrets hardcoded in source code
- [ ] No secrets in logs

### API Tokens
- [ ] Discord bot token valid and scoped appropriately
- [ ] Linear API key has minimum required permissions
- [ ] GitHub token (if used) has minimum scopes
- [ ] Webhook secrets configured for signature verification

### Application Runtime
- [ ] Application runs as non-root user
- [ ] Working directory permissions restricted
- [ ] Log files not world-readable
- [ ] No sensitive data in application logs

## Network Security

### HTTPS/TLS
- [ ] SSL certificate installed (Let's Encrypt)
- [ ] Certificate auto-renewal configured
- [ ] HTTP redirects to HTTPS
- [ ] TLS 1.2+ only (no TLS 1.0/1.1)
- [ ] Strong cipher suite configured

### Webhook Security
- [ ] Linear webhook signature verification enabled
- [ ] GitHub webhook signature verification enabled (if used)
- [ ] Webhook endpoints not publicly listed
- [ ] Rate limiting on webhook endpoints

### DNS
- [ ] DNS records point to correct server
- [ ] CAA records set (optional)
- [ ] No unnecessary DNS records exposed

## Monitoring & Logging

### Audit Logging
- [ ] SSH login attempts logged
- [ ] sudo commands logged
- [ ] Application actions logged
- [ ] Logs retained for appropriate period

### Alerting
- [ ] Failed login alerts configured
- [ ] Application error alerts configured
- [ ] Disk space alerts configured
- [ ] Service down alerts configured

## Post-Deployment Verification

### Verify SSH Hardening
```bash
# Try password login (should fail)
ssh -o PreferredAuthentications=password user@server

# Try root login (should fail)
ssh root@server

# Check sshd config
grep -E "PermitRootLogin|PasswordAuthentication" /etc/ssh/sshd_config
```

### Verify Firewall
```bash
# Check UFW status
ufw status verbose

# Scan for open ports (from external machine)
nmap -p- server-ip
```

### Verify fail2ban
```bash
# Check status
fail2ban-client status sshd

# Check banned IPs
fail2ban-client status sshd | grep "Banned"
```

### Verify Application
```bash
# Check running user
ps aux | grep node

# Check file permissions
ls -la /opt/devrel-integration/secrets/

# Check for secrets in logs
grep -i "token\|key\|secret\|password" /var/log/devrel/*.log
```

## Regular Security Tasks

### Weekly
- [ ] Review fail2ban banned IPs
- [ ] Check for failed SSH attempts
- [ ] Review application error logs

### Monthly
- [ ] Apply system security updates
- [ ] Review user access list
- [ ] Verify backup integrity
- [ ] Check SSL certificate expiry

### Quarterly
- [ ] Rotate API tokens
- [ ] Review and update firewall rules
- [ ] Audit installed packages
- [ ] Review security logs comprehensively

## Incident Response

### If Compromise Suspected

1. **Isolate**: Block network access
   ```bash
   ufw default deny incoming
   ufw default deny outgoing
   ufw allow from YOUR_IP
   ```

2. **Preserve Evidence**: Copy logs
   ```bash
   cp -r /var/log /root/incident-$(date +%Y%m%d)
   ```

3. **Investigate**: Review logs
   ```bash
   last -50
   cat /var/log/auth.log
   history
   ```

4. **Rotate Credentials**: Immediately rotate all API tokens

5. **Document**: Record timeline and findings

6. **Report**: Notify appropriate parties

## Security Contacts

- **Security Issues**: [security@yourcompany.com]
- **On-Call**: [oncall@yourcompany.com]
- **Emergency**: [emergency contact]

---

**Last Security Review**: _______________
**Next Review Due**: _______________
**Reviewed By**: _______________
