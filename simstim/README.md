# Simstim

> Telegram Bridge for Remote Loa (Claude Code) Monitoring and Control

Simstim provides a mobile-friendly interface for monitoring and controlling your Loa (Claude Code) sessions remotely via Telegram. Named after the neural interface technology in William Gibson's Sprawl trilogy, Simstim lets you experience your AI agent workflows from anywhere.

## Features

- **Permission Relay**: Receive permission prompts on Telegram, approve/deny with one tap
- **Auto-Approve Policies**: Configure patterns to automatically approve safe operations
- **Phase Monitoring**: Get notified when Loa transitions between workflow phases
- **Quality Gates**: Receive notifications for review/audit feedback
- **Rate Limiting**: Per-user rate limiting with denial backoff
- **Offline Support**: Queue events during disconnection, auto-reconnect
- **Audit Logging**: Comprehensive JSONL logging for all events

## Installation

```bash
# Install from PyPI (recommended)
pip install simstim

# Or install from source
git clone https://github.com/0xHoneyJar/simstim
cd simstim
pip install -e .
```

## Quick Start

### 1. Create a Telegram Bot

1. Message [@BotFather](https://t.me/BotFather) on Telegram
2. Send `/newbot` and follow the prompts
3. Save the bot token you receive

### 2. Get Your Chat ID

1. Message your new bot
2. Run: `curl "https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates"`
3. Find your `chat.id` in the response

### 3. Configure Simstim

```bash
# Set environment variable
export SIMSTIM_BOT_TOKEN="your-bot-token"

# Create configuration
simstim config --init

# Edit simstim.toml with your settings
```

### 4. Start the Bridge

```bash
# Start with default configuration
simstim start

# Or specify a config file
simstim start --config /path/to/simstim.toml

# Start Loa with a specific command
simstim start -- /implement sprint-1
```

## Configuration

Create a `simstim.toml` file:

```toml
[telegram]
bot_token = "${SIMSTIM_BOT_TOKEN}"  # Environment variable expansion
chat_id = 123456789  # Your chat ID

[security]
authorized_users = [123456789]  # Allowed Telegram user IDs
redact_patterns = ["password", "secret", "token", "api_key"]
log_unauthorized_attempts = true

[timeouts]
permission_timeout_seconds = 300  # 5 minutes
default_action = "deny"  # "approve" or "deny" on timeout

[notifications]
phase_transitions = true
quality_gates = true
notes_updates = false

[loa]
command = "claude"
working_directory = "."

# Auto-approve policies
[[policies]]
name = "approve-src-files"
enabled = true
action = "file_create"
pattern = "src/**/*.{ts,tsx,js,jsx}"
max_risk = "medium"

[[policies]]
name = "approve-tests"
enabled = true
action = "file_edit"
pattern = "tests/**/*.py"
max_risk = "low"

[audit]
enabled = true
log_path = "simstim-audit.jsonl"
max_file_size_mb = 100
rotate_count = 5

[reconnection]
initial_delay = 1.0
max_delay = 300.0
backoff_factor = 2.0

[rate_limit]
requests_per_minute = 30
denial_backoff_base = 5.0
denial_threshold = 3
```

## Telegram Commands

| Command | Description |
|---------|-------------|
| `/start` | Initialize connection |
| `/status` | Show bridge status and statistics |
| `/halt` | Signal Loa to stop gracefully |
| `/start_phase /impl sprint-1` | Send a command to Loa |
| `/policies` | List active auto-approve policies |
| `/help` | Show help |

## Risk Levels

Simstim assesses risk for each permission request:

| Level | Emoji | Description |
|-------|-------|-------------|
| Low | 🟢 | Safe operations (reading, tests) |
| Medium | 🟡 | Standard file operations |
| High | 🟠 | System modifications, deletions |
| Critical | 🔴 | Sensitive system changes |

## Auto-Approve Policies

Configure policies to automatically approve matching requests:

```toml
[[policies]]
name = "approve-source-files"
enabled = true
action = "file_edit"  # file_create, file_edit, file_delete, bash_execute, mcp_tool
pattern = "src/**/*.ts"  # Glob patterns with brace expansion
max_risk = "medium"  # Maximum risk level to auto-approve
```

**Pattern Examples**:
- `*.ts` - All TypeScript files in root
- `src/**/*.{ts,tsx}` - All TS/TSX files in src and subdirectories
- `tests/*.py` - Test files in tests directory only

## Architecture

Simstim follows a Gibson Sprawl naming convention:

| Component | Role | Class |
|-----------|------|-------|
| **Deck** | Main orchestrator | `Deck` |
| **Jack** | Loa PTY monitor | `LoaMonitor` |
| **Finn** | Telegram bot handler | `SimstimBot` |
| **ICE** | Policy engine | `PolicyEngine` |

```
┌─────────────────────────────────────────────┐
│                   Deck                       │
│         (Main Orchestrator)                  │
├──────────────┬──────────────┬───────────────┤
│     Jack     │     Finn     │     ICE       │
│  LoaMonitor  │  TelegramBot │ PolicyEngine  │
│              │              │               │
│  PTY/Stdout  │  Commands    │  Auto-approve │
│  Injection   │  Callbacks   │  Evaluation   │
└──────┬───────┴──────┬───────┴───────────────┘
       │              │
       ▼              ▼
   Loa Process    Telegram API
```

## CLI Reference

```bash
simstim start [OPTIONS] [-- INITIAL_COMMAND]
  Start the Simstim bridge

  Options:
    --config PATH    Configuration file path
    --foreground     Run in foreground (default)
    --background     Run in background (daemonize)

simstim stop
  Stop a running Simstim bridge

simstim status
  Show status of running bridge

simstim config --init
  Create a default configuration file

simstim version
  Show version information
```

## Audit Log Format

Simstim writes audit logs in JSONL format:

```json
{"timestamp": "2026-01-20T12:00:00Z", "event_type": "permission_requested", "request_id": "abc123", "action": "file_edit", "target": "src/main.ts", "risk_level": "low"}
{"timestamp": "2026-01-20T12:00:05Z", "event_type": "permission_approved", "request_id": "abc123", "user_id": 123456789}
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `SIMSTIM_BOT_TOKEN` | Telegram bot token | Required |
| `SIMSTIM_CONFIG` | Config file path | `simstim.toml` |
| `SIMSTIM_LOG_LEVEL` | Logging level | `INFO` |

## Security Considerations

- **Never commit bot tokens** to version control
- Use environment variables for sensitive values
- Configure `authorized_users` to restrict access
- Review auto-approve policies carefully
- Enable `log_unauthorized_attempts` for security monitoring

## Development

```bash
# Clone repository
git clone https://github.com/0xHoneyJar/simstim
cd simstim

# Install in development mode
pip install -e ".[dev]"

# Run tests
pytest

# Run type checks
mypy src/simstim

# Format code
ruff format src tests
ruff check src tests --fix
```

## License

MIT License - see [LICENSE](LICENSE) for details.

## Related Projects

- [Loa](https://github.com/0xHoneyJar/loa) - Agent-driven development framework
- [Claude Code](https://claude.com/claude-code) - Anthropic's CLI for Claude
