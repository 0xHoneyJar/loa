# Security

## Reporting Security Vulnerabilities

If you discover a security vulnerability in Simstim, please report it responsibly by emailing security@thj.dev. Do not open a public issue.

## Security Design

### Authentication

- **Telegram Bot Token**: Must be stored in `SIMSTIM_BOT_TOKEN` environment variable, never in configuration files
- **Authorized Users**: Configure `security.authorized_users` to restrict who can interact with the bot
- **Unauthorized Attempts**: Enable `security.log_unauthorized_attempts` to audit unauthorized access

### Data Protection

- **Sensitive Redaction**: Configure `security.redact_patterns` to redact sensitive strings from notifications
- **Default Patterns**: `password`, `secret`, `token`, `api_key` are redacted by default
- **Token Display**: Bot token is never displayed in full (always masked)

### Process Isolation

- **PTY Isolation**: Loa runs in a PTY wrapper, isolated from the Simstim process
- **No Privilege Escalation**: Simstim never requests or uses elevated privileges
- **Input Injection**: Only `y` or `n` characters are injected to Loa

### Audit Trail

- **JSONL Logging**: All events logged in structured JSONL format
- **Log Rotation**: Automatic rotation prevents unbounded log growth
- **Event Types**: Permission requests, approvals, denials, phase transitions all logged

### Rate Limiting

- **Per-User Limits**: Default 30 requests/minute per Telegram user
- **Denial Backoff**: Repeated denials increase wait time
- **Abuse Prevention**: Protects against automated attacks

## Security Checklist for Deployment

- [ ] Bot token stored in environment variable only
- [ ] `authorized_users` configured with specific Telegram user IDs
- [ ] `redact_patterns` configured for project-specific secrets
- [ ] Audit logging enabled with appropriate rotation
- [ ] Review auto-approve policies for security implications
- [ ] Never expose bot token in logs or error messages
- [ ] Use private bot (disable group joins)
- [ ] Regularly review audit logs

## Threat Model

| Threat | Mitigation |
|--------|------------|
| Unauthorized Telegram user | `authorized_users` whitelist |
| Token theft | Environment variable only, masked display |
| Credential exposure in notifications | `redact_patterns` configuration |
| Replay attacks | Callback query validation |
| Rate limit bypass | Per-user sliding window |
| Man-in-the-middle | Telegram API uses TLS |
| Audit log tampering | Write-only, no delete operations |

## Dependencies

All dependencies are from trusted sources (PyPI) with pinned minimum versions:

| Dependency | Security Notes |
|------------|----------------|
| python-telegram-bot | Official Telegram Python library |
| ptyprocess | POSIX PTY handling, no network access |
| pydantic | Data validation, no network access |
| typer | CLI parsing, no network access |
| structlog | Logging, no network access |
| rich | Terminal output, no network access |

## Security Audit History

| Date | Scope | Findings | Status |
|------|-------|----------|--------|
| 2026-01-20 | Initial release | None | ✅ Passed |
