# Browsing Constructs Skill

## Purpose

Provide a multi-select UI for browsing and installing packs from the Loa Constructs Registry. Enables composable skill installation per-repo.

## Invocation

- `/constructs` - Browse and install packs (default)
- `/constructs browse` - Browse available packs with selection UI
- `/constructs install <pack>` - Install specific pack directly
- `/constructs list` - List installed packs
- `/constructs update` - Check for updates
- `/constructs uninstall <pack>` - Remove a pack
- `/constructs auth` - Check authentication status
- `/constructs auth setup` - Set up API key for premium packs

## Workflow

### Action: auth

Check or set up authentication for premium packs.

#### auth (no args) - Check Status

```bash
.claude/scripts/constructs-auth.sh status
```

Display authentication status:
- Whether authenticated
- Key source (env var or credentials file)
- Masked key preview

#### auth setup - Configure API Key

Guide user through API key setup using AskUserQuestion:

```json
{
  "questions": [{
    "question": "Enter your Constructs API key (get from loa-constructs.dev/account):",
    "header": "API Key",
    "multiSelect": false,
    "options": [
      {
        "label": "I have my API key ready",
        "description": "Paste your sk_... key when prompted"
      },
      {
        "label": "I need to get a key first",
        "description": "Opens browser to loa-constructs.dev/account"
      },
      {
        "label": "Skip for now",
        "description": "Free packs will still be available"
      }
    ]
  }]
}
```

If user has key, prompt for it and run:
```bash
.claude/scripts/constructs-auth.sh setup <api_key>
```

### Action: browse (default)

#### Phase 0: Check Authentication

First, check auth status to determine which packs to show:

```bash
auth_status=$(.claude/scripts/constructs-auth.sh status --json)
is_authenticated=$(echo "$auth_status" | jq -r '.authenticated')
```

If not authenticated, show a note about premium packs requiring auth.

#### Phase 1: Fetch Available Packs

Run the browse script to get available packs:

```bash
packs_json=$(.claude/scripts/constructs-browse.sh list --json)
```

This returns a JSON array of packs with:
- `slug` - Pack identifier
- `name` - Display name
- `description` - One-line description
- `skills_count` - Number of skills included
- `tier` - "free" or "pro"
- `icon` - Emoji icon

#### Phase 2: Check Installed Packs

Check which packs are already installed:

```bash
installed=$(.claude/scripts/constructs-loader.sh list --json 2>/dev/null || echo "[]")
```

#### Phase 3: Present Pack Selection Table

Display ALL available packs in a numbered markdown table, then use AskUserQuestion for selection.

**Step 3a: Render Pack Table**

Generate a markdown table from the packs JSON:

```markdown
## Available Packs

| # | Pack | Skills | Tier | Status |
|---|------|--------|------|--------|
| 1 | 🔮 Observer | 6 | Free | |
| 2 | ⚗️ Crucible | 5 | Free | |
| 3 | 🎨 Artisan | 10 | Pro | Installed |
| 4 | 🚀 GTM Collective | 8 | Free | |
| 5 | 🔔 Sigil of the Beacon | 6 | Free | |
```

**Table columns:**
- `#` - Row number (1-indexed)
- `Pack` - Icon + name
- `Skills` - Number of skills in pack
- `Tier` - "Free" or "Pro"
- `Status` - "Installed" if already installed, empty otherwise

**Step 3b: Selection Prompt**

Use AskUserQuestion with 3 options (NOT multiSelect):

```json
{
  "questions": [{
    "question": "How would you like to install packs?",
    "header": "Install",
    "multiSelect": false,
    "options": [
      {
        "label": "Enter pack numbers",
        "description": "Type numbers like: 1,3,5"
      },
      {
        "label": "Install all",
        "description": "Install all available packs"
      },
      {
        "label": "Cancel",
        "description": "Exit without installing"
      }
    ]
  }]
}
```

**Step 3c: Parse User Input**

If user selects "Enter pack numbers":
1. Prompt: "Enter pack numbers (comma-separated):"
2. Parse the input using this grammar:
   ```
   input     ::= "all" | selection | ""
   selection ::= number ("," number)*
   number    ::= [0-9]+
   ```
3. Trim whitespace from input and between commas
4. Convert each token to integer
5. Validate: `1 <= n <= pack_count`
6. Filter: Skip already-installed packs

**Step 3d: Confirmation (Required)**

Before installing, echo back the resolved selection:

```
You selected:
  - Observer (#1)
  - Artisan (#3)

Proceed with installation? [Y/n]
```

**Retry Limits:**
- Max 3 invalid input attempts
- After 3 failures, abort with message: "Too many invalid attempts. Run `/constructs browse` to try again."

**Edge Cases:**

| Input | Behavior |
|-------|----------|
| `"1,3,5"` | Install packs 1, 3, 5 |
| `"all"` | Install all non-installed packs |
| `"1, 3, 5"` | Same as "1,3,5" (whitespace tolerant) |
| `"1,99,3"` | Warn about 99, install 1 and 3 |
| `""` | Re-prompt (counts as invalid attempt) |
| `"abc"` | Error, re-prompt (counts as invalid attempt) |
| 3 failures | Abort with "Too many invalid attempts" |

#### Phase 4: Install Selected Packs

For each selected pack, run installation:

```bash
.claude/scripts/constructs-install.sh pack <slug>
```

Capture output and track:
- Success/failure per pack
- Skills installed
- Commands available

#### Phase 5: Report Results

Present installation summary:

```
╭───────────────────────────────────────────────────────────────╮
│  INSTALLATION COMPLETE                                        │
╰───────────────────────────────────────────────────────────────╯

✅ Observer (6 skills installed)
   Commands: /interview, /persona, /journey, /pain-points, /user-story, /empathy-map

✅ Crucible (5 skills installed)
   Commands: /test-plan, /quality-gate, /acceptance, /regression, /smoke-test

Total: 2 packs, 11 skills
```

### Action: install <pack>

Direct installation without UI:

1. Validate pack slug provided
2. Run: `.claude/scripts/constructs-install.sh pack <pack>`
3. Report result

### Action: list

Show installed packs:

```bash
.claude/scripts/constructs-loader.sh list
```

### Action: update

Check for newer versions:

```bash
.claude/scripts/constructs-loader.sh check-updates
```

### Action: uninstall <pack>

Remove installed pack:

1. Confirm with user (AskUserQuestion)
2. Run: `.claude/scripts/constructs-install.sh uninstall pack <pack>`
3. Report result

## Error Handling

| Error | Handling |
|-------|----------|
| No network | Use cached pack list if available |
| No API key | Show free packs only, note premium requires auth, offer `/constructs auth setup` |
| Invalid API key | Prompt to re-authenticate with `/constructs auth setup` |
| Pack not found | Suggest similar packs or list available |
| Premium pack without auth | Explain pack requires subscription, offer auth setup |
| Install fails | Show error, continue with other selections |

### Premium Pack Handling

When user selects a premium pack without authentication:

1. Check pack tier before installation
2. If tier is "pro" and not authenticated:
   - Display message: "🔒 {pack_name} requires a subscription"
   - Offer options via AskUserQuestion:
     - "Set up API key now" → `/constructs auth setup`
     - "Skip this pack" → Continue with free packs only
     - "Cancel" → Abort installation

## UI Guidelines

### Pack Selection Display

When building AskUserQuestion options:

1. **Icon first**: Visual differentiation
2. **Name prominent**: Easy scanning
3. **Count in parens**: "(N skills)"
4. **Description**: What it does
5. **Status**: Installed marker if applicable

### Scalable Pack Display

The table-based approach handles unlimited packs:
- ALL packs displayed in numbered table (no 4-option limit)
- User selects by entering numbers (comma-separated)
- Supports "all" keyword for bulk installation
- Confirmation step before installation

### Tier Indicators

- Free packs: No special indicator
- Pro packs: Add "(Pro)" to label or "🔒 Requires subscription" to description

## Per-Repo State

Installed packs go to `.claude/constructs/packs/` which is gitignored.

Installation metadata tracked in `.constructs-meta.json`:
```json
{
  "installed_packs": {
    "observer": {
      "version": "1.0.0",
      "installed_at": "2026-01-31T12:00:00Z"
    }
  }
}
```

## Related Scripts

- `.claude/scripts/constructs-auth.sh` - Authentication management
- `.claude/scripts/constructs-browse.sh` - Pack discovery
- `.claude/scripts/constructs-install.sh` - Installation
- `.claude/scripts/constructs-loader.sh` - Skill loading
- `.claude/scripts/constructs-lib.sh` - Shared utilities

## Authentication Methods

API keys can be configured in three ways (checked in order):

1. **Environment variable** (recommended for CI/CD):
   ```bash
   export LOA_CONSTRUCTS_API_KEY=sk_live_xxxxxxxxxxxx
   ```

2. **Credentials file** (recommended for local development):
   ```bash
   # Created by /constructs auth setup
   ~/.loa/credentials.json
   ```

3. **Alternative credentials** (legacy):
   ```bash
   ~/.loa-constructs/credentials.json
   ```

### Getting an API Key

1. Visit https://loa-constructs.dev/account
2. Sign in or create an account
3. Generate an API key
4. Run `/constructs auth setup` and paste the key
