# Browsing Constructs Skill

## Purpose

Unified construct discovery surface for the Constructs Network. This skill is a **thin API client** — all search intelligence, ranking, and composability analysis lives in the Constructs Network API.

## API Configuration

- **Base URL**: `LOA_CONSTRUCTS_API_URL` env var, default `https://api.constructs.network/v1`
- **Auth**: `LOA_CONSTRUCTS_API_KEY` env var or `~/.loa/credentials.json` (for premium packs)

## Invocation

### `/constructs` (no args) — Browse-First Discovery

Fetch the full catalog and display grouped by category.

**API call:**
```
GET {API}/constructs?per_page=100&include_composability=true
```

**Output format:**
```
Constructs Network — 23 constructs

  design (8)
    🎨 artisan (14 skills) — Design systems craft
    🖼️ the-easel (4 skills) — Aesthetic direction studio
    ⚒️ the-mint (8 skills) — Material transformation pipeline

  security (3)
    🛡️ hardening (7 skills) — Defensive artifact forge
    🧪 crucible (5 skills) — Journey validation testing
    🔑 dynamic-auth (3 skills) — Wallet identity resolution

  research (2)
    🕳️ k-hole (2 skills) — Non-extractive pair research
    🦎 gecko (3 skills) — Autonomous ecosystem intelligence

  ...

Browse: constructs.network/constructs
```

**Grouping rules:**
1. Group constructs by `category` field from API response
2. Sort categories alphabetically
3. Within each category, sort by skill count descending
4. Show category name with construct count in parens
5. Each construct line: icon + slug + (N skills) + em-dash + short description

---

### `/constructs <natural query>` — Intent Search

Fetch ranked results matching the user's natural language query.

**API call:**
```
GET {API}/constructs?q={query}&include_skills=true&include_composability=true
```

**Output format:**
```
Constructs Network — 23 constructs

Matching "security audit":

  🛡️ hardening (7 skills) [VERIFIED]
     Defensive artifact forge
     Skills: /threat-model  /security-review  /pen-test  /postmortem
     Works with: observer → protocol
     Install: /constructs install hardening

  🧪 crucible (5 skills) [COMMUNITY]
     Journey validation testing
     Skills: /validate  /test-journey  /detect-gaps
     Works with: observer ↔ (circular)
     Install: /constructs install crucible

Browse: constructs.network/constructs?q=security+audit
```

**Display rules:**
1. Show results in API-returned rank order (most relevant first)
2. Include verification tier in brackets: `[VERIFIED]`, `[COMMUNITY]`, `[UNVERIFIED]`
3. List up to 4 skill commands inline (truncate with `...` if more)
4. Show composability edges using arrows: `→` (depends on), `←` (depended by), `↔` (circular)
5. Include install command for each result

**Zero results:** If the API returns no matches, output:
```
No constructs match "<query>".
Try: npx skills find <query>
```

---

### `/constructs compose` — Composability View

Show what constructs pair with currently installed constructs.

**Steps:**
1. Detect installed constructs:
   ```bash
   installed=$(.claude/scripts/constructs-loader.sh list 2>/dev/null)
   ```
2. Fetch all constructs with composability:
   ```
   GET {API}/constructs?per_page=100&include_composability=true
   ```
3. Filter to show only constructs that have composability edges with installed ones

**Output format:**
```
Composability for your installed constructs:

  You have: observer, artisan

  Works with observer:
    → crucible (required, circular) — Journey validation testing
    → hardening (depends on observer) — Defensive artifact forge
    → protocol (depends on observer) — On-chain verification

  Works with artisan:
    → the-easel (depends on artisan) — Aesthetic direction studio
    → the-speakers (optional) — Psychoacoustic engineering

  Install: /constructs install <slug>
```

**Edge cases:**
- No constructs installed: "No constructs installed. Run `/constructs` to browse."
- Installed constructs have no composability edges: "Your constructs have no declared composability relationships."

---

### `/constructs install <slug>` — Install

Direct installation without browse UI.

1. Validate pack slug provided
2. Run: `.claude/scripts/constructs-install.sh pack <slug>`
3. Report result with installed skill commands

---

### `/constructs register` — Register

Register a new construct with the network. Delegates to existing registration flow.

---

### `/constructs sync` — Sync

Sync installed constructs with the registry. Delegates to existing sync flow.

---

### `/constructs status` — Status

Show status of installed constructs, versions, and update availability.

```bash
.claude/scripts/constructs-loader.sh list
.claude/scripts/constructs-loader.sh check-updates
```

---

### `/constructs auth` — Authentication

Check or set up authentication for premium packs.

#### auth (no args) — Check Status
```bash
.claude/scripts/constructs-auth.sh status
```

#### auth setup — Configure API Key

Guide user through API key setup. Keys from: `LOA_CONSTRUCTS_API_KEY` env var, `~/.loa/credentials.json`, or `~/.loa-constructs/credentials.json` (legacy).

```bash
.claude/scripts/constructs-auth.sh setup <api_key>
```

## Passive Triggers

This skill should activate (with search mode) when the user says things like:
- "find a skill for ..."
- "find a construct ..."
- "I need help with ..."
- "is there a construct that ..."
- "what construct can ..."
- "search constructs ..."

When a passive trigger fires, treat the trailing text as the search query and execute the `/constructs <query>` flow.

## API Response Shape

The skill expects the API to return constructs in this shape:

```json
{
  "data": [
    {
      "slug": "hardening",
      "name": "Hardening",
      "description": "Defensive artifact forge",
      "icon": "🛡️",
      "category": "security",
      "skills_count": 7,
      "verification_tier": "VERIFIED",
      "skills": [
        { "slug": "threat-model", "command": "/threat-model" }
      ],
      "composability": {
        "depends_on": ["observer"],
        "depended_by": ["protocol"],
        "optional": []
      }
    }
  ],
  "meta": {
    "total": 23,
    "page": 1,
    "per_page": 100
  }
}
```

If the API returns a different shape, adapt gracefully. The `skills` and `composability` fields are only present when `include_skills=true` and `include_composability=true` query params are set.

## Error Handling

| Error | Handling |
|-------|----------|
| Network failure | Show error, suggest retrying. If cached data available, use it. |
| API returns 401 | "Authentication required for this operation. Run `/constructs auth setup`." |
| API returns 404 | "Construct not found. Run `/constructs` to browse available constructs." |
| API returns 500 | "Constructs Network API error. Try again later." |
| No `LOA_CONSTRUCTS_API_URL` set | Use default `https://api.constructs.network/v1` |

## Per-Repo State

Installed packs go to `.claude/constructs/packs/` which is gitignored.

Installation metadata tracked in `.constructs-meta.json`.

## Related Scripts

- `.claude/scripts/constructs-auth.sh` — Authentication management
- `.claude/scripts/constructs-browse.sh` — Pack discovery (legacy, prefer API)
- `.claude/scripts/constructs-install.sh` — Installation
- `.claude/scripts/constructs-loader.sh` — Skill loading
- `.claude/scripts/constructs-lib.sh` — Shared utilities
