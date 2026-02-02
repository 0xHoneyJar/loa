# NotebookLM Authentication Setup

This guide explains how to set up Google authentication for the NotebookLM knowledge retrieval skill.

## Overview

NotebookLM requires Google account authentication. This skill uses persistent browser sessions to maintain authentication across invocations, eliminating the need to re-authenticate each time.

## Prerequisites

1. **Google Account** with access to NotebookLM
2. **Chromium browser** installed on your system
3. **Python 3.10+** with Patchright installed

### Installing Dependencies

```bash
# Install Patchright
pip install patchright

# Install Patchright browser (downloads Chromium)
python -m patchright install chromium
```

## Initial Authentication

### Step 1: Run Setup Command

```bash
cd .claude/skills/flatline-knowledge/resources
python notebooklm-query.py --setup-auth
```

### Step 2: Complete Google Sign-In

A browser window will open. Follow these steps:

1. Click "Sign in with Google" on the NotebookLM page
2. Enter your Google account credentials
3. Complete any 2FA verification if prompted
4. Wait for the NotebookLM dashboard to load
5. **Close the browser window** when done

### Step 3: Verify Authentication

```bash
# Test with a dry run
python notebooklm-query.py --domain "test" --phase prd --dry-run

# Test with actual query (requires notebook)
python notebooklm-query.py --domain "authentication" --phase sdd --no-headless
```

## Session Storage

Authentication sessions are stored in:

```
~/.claude/notebooklm-auth/
├── Default/
│   ├── Cookies
│   ├── Local Storage/
│   ├── Session Storage/
│   └── ...
└── ...
```

### Security Considerations

- **Local storage only**: Session data stays on your machine
- **Encrypted cookies**: Chromium encrypts cookies at rest
- **No credential storage**: Your Google password is NOT stored
- **Session expiry**: Google sessions may expire after extended periods

### Protecting Session Data

```bash
# Restrict permissions to your user only
chmod 700 ~/.claude/notebooklm-auth
chmod -R 600 ~/.claude/notebooklm-auth/*
```

## Re-Authentication

Sessions may expire due to:
- Google security policies (periodic re-auth)
- Browser data corruption
- Manual sign-out in another browser

### Signs of Expired Session

You'll see this error:
```
Error (auth_expired): Google authentication expired. Run with --setup-auth
```

### Refresh Process

1. Delete old session (optional but recommended):
   ```bash
   rm -rf ~/.claude/notebooklm-auth
   ```

2. Re-run setup:
   ```bash
   python notebooklm-query.py --setup-auth
   ```

## Multiple Accounts

If you need to use different Google accounts:

```bash
# Create separate auth directories
python notebooklm-query.py --setup-auth --auth-dir ~/.claude/notebooklm-auth-work
python notebooklm-query.py --setup-auth --auth-dir ~/.claude/notebooklm-auth-personal

# Query with specific account
python notebooklm-query.py --domain "..." --phase prd --auth-dir ~/.claude/notebooklm-auth-work
```

## Privacy Implications

By using this skill, be aware that:

1. **Google Account Link**: Your NotebookLM queries are associated with your Google account
2. **Query History**: Google may log queries made to NotebookLM
3. **Session Data**: Browser data (cookies, local storage) is stored locally
4. **No Loa Logging**: By default, Loa does not log your NotebookLM queries

### Opt-Out

If you're uncomfortable with these implications:

1. Keep NotebookLM disabled (default):
   ```yaml
   # .loa.config.yaml
   flatline_protocol:
     knowledge:
       notebooklm:
         enabled: false  # Default
   ```

2. The Flatline Protocol will use local knowledge only (Tier 1), which has no external dependencies.

## Troubleshooting

### "Patchright not installed"

```bash
pip install patchright
python -m patchright install chromium
```

### "Browser not found"

Ensure Chromium is accessible:
```bash
# Check if Chromium is installed
which chromium || which chromium-browser || which google-chrome

# If not, install it
# Ubuntu/Debian:
sudo apt install chromium-browser

# macOS:
brew install chromium

# Or let Patchright install it:
python -m patchright install chromium
```

### "Timeout waiting for response"

This can happen if:
- Network is slow
- NotebookLM service is overloaded
- Query is complex

Try:
```bash
# Increase timeout
python notebooklm-query.py --domain "..." --phase prd --timeout 60000

# Run in visible mode to debug
python notebooklm-query.py --domain "..." --phase prd --no-headless
```

### "Could not find query input"

NotebookLM's UI may have changed. Try:
1. Update Patchright: `pip install --upgrade patchright`
2. Run in visible mode to see the UI
3. Report issue if persistent

### Session Corruption

If you see strange behavior:
```bash
# Clear session and re-authenticate
rm -rf ~/.claude/notebooklm-auth
python notebooklm-query.py --setup-auth
```

## Configuration Reference

In `.loa.config.yaml`:

```yaml
flatline_protocol:
  knowledge:
    notebooklm:
      enabled: false          # Enable NotebookLM integration
      notebook_id: ""         # Default notebook ID to query
      timeout_ms: 30000       # Query timeout (default: 30s)
      headless: true          # Run browser in headless mode
      auth_dir: ""            # Custom auth directory (optional)
```

## Related Documentation

- [Flatline Knowledge Skill](../SKILL.md) - Full skill documentation
- [Flatline Protocol](../../../../grimoires/loa/prd.md) - PRD for the overall protocol
- [Patchright Documentation](https://github.com/AISafetyLab/patchright) - Browser automation library
