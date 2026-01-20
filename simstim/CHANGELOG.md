# Changelog

All notable changes to Simstim will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-01-20

### Added

- **Core Infrastructure**
  - Configuration management with TOML support and environment variable expansion
  - Permission prompt parser with 5 action types (FILE_CREATE, FILE_EDIT, FILE_DELETE, BASH_EXECUTE, MCP_TOOL)
  - Async permission queue with timeout and cleanup
  - PTY wrapper for Loa process management

- **Telegram Integration**
  - Full Telegram bot with `/start`, `/status`, `/halt` commands
  - Permission request notifications with approve/deny inline buttons
  - Risk level indicators (🟢 Low, 🟡 Medium, 🟠 High, 🔴 Critical)
  - User authorization and security checks
  - Sensitive content redaction

- **Policy Engine**
  - Auto-approve policies with glob pattern matching
  - Brace expansion support (e.g., `*.{ts,tsx}`)
  - Risk level thresholds for auto-approval
  - Phase detection and notifications
  - Remote phase initiation via `/start_phase` command

- **Hardening & Reliability**
  - Structured audit logging in JSONL format
  - Log file rotation
  - Offline event queue with priority handling
  - Automatic reconnection with exponential backoff
  - Per-user rate limiting with denial backoff

- **Quality Gate Integration**
  - Parser for `engineer-feedback.md` and `auditor-sprint-feedback.md`
  - Finding extraction with severity levels
  - NOTES.md parser for Current Focus, Blockers, Decisions
  - Telegram notifications for quality gate status
  - Deep link generation (file://, vscode://, cursor://, github://)

- **CLI**
  - `simstim start` - Start the bridge
  - `simstim stop` - Stop running bridge
  - `simstim status` - Show bridge status
  - `simstim config --init` - Create default configuration
  - `simstim config --validate` - Validate configuration
  - `simstim version` - Show version
  - `simstim doctor` - System health check
  - `simstim test-patterns` - Test permission detection patterns

### Security

- Bot token stored in environment variable only
- Authorized users whitelist
- Sensitive data redaction in notifications
- Comprehensive audit trail
- Rate limiting to prevent abuse

---

## Naming Convention

Simstim follows the Gibson Sprawl naming theme:

| Component | Role | Class |
|-----------|------|-------|
| **Deck** | Main orchestrator | `Deck` |
| **Jack** | Loa PTY monitor | `LoaMonitor` |
| **Finn** | Telegram bot handler | `SimstimBot` |
| **ICE** | Policy engine | `PolicyEngine` |

Named after the simstim neural interface technology from William Gibson's Sprawl trilogy.
