# Discord Security Documentation

**Status**: ✅ APPROVED
**Version**: 1.0
**Last Updated**: December 8, 2025
**Owner**: Security Team
**Review Schedule**: Quarterly

---

## Table of Contents

1. [Overview](#overview)
2. [Discord Server Structure](#discord-server-structure)
3. [Channel Access Controls](#channel-access-controls)
4. [Role Definitions and Permissions](#role-definitions-and-permissions)
5. [Bot Permissions](#bot-permissions)
6. [Message Retention Policy](#message-retention-policy)
7. [Quarterly Audit Procedures](#quarterly-audit-procedures)
8. [Security Best Practices](#security-best-practices)
9. [Incident Response](#incident-response)
10. [Compliance Requirements](#compliance-requirements)

---

## Overview

This document defines the security controls and access policies for the Agentic-Base Discord server. The server facilitates team communication, stakeholder updates, and automated notifications through a secure Discord bot integration.

### Security Objectives

1. **Confidentiality**: Protect sensitive project information from unauthorized access
2. **Integrity**: Prevent unauthorized modification of messages and bot configuration
3. **Availability**: Ensure reliable communication channel for team and stakeholders
4. **Auditability**: Maintain complete audit trail of access and permission changes
5. **Compliance**: Meet GDPR, SOC 2, and organizational security requirements

### Scope

This document covers:
- Discord server and channel configuration
- Role-based access control (RBAC)
- Bot permissions and security
- Message retention and data lifecycle
- Audit procedures and compliance

---

## Discord Server Structure

### Channel Hierarchy

```
Agentic-Base Discord Server/
├── 📋 STAKEHOLDER COMMUNICATION
│   └── #exec-summary          [RESTRICTED] Executive and stakeholder updates
│
├── 🛠️ ENGINEERING
│   ├── #engineering           [INTERNAL] Technical discussions
│   ├── #sprint-updates        [INTERNAL] Sprint status and planning
│   └── #linear-notifications  [INTERNAL] Automated Linear issue updates
│
├── 📊 PRODUCT & DESIGN
│   ├── #product               [INTERNAL] Product discussions
│   └── #design                [INTERNAL] Design reviews
│
├── 📣 MARKETING
│   └── #marketing             [INTERNAL] Marketing discussions and campaigns
│
├── 🔐 ADMIN
│   ├── #admin-only            [ADMIN ONLY] Administrative operations
│   ├── #security-alerts       [ADMIN ONLY] Security notifications
│   └── #audit-logs            [ADMIN ONLY] Bot and server audit logs
│
└── 🌐 PUBLIC
    ├── #general               [PUBLIC] General team chat
    └── #help                  [PUBLIC] Bot help and usage questions
```

### Channel Categories

| Category | Purpose | Access Level | Data Sensitivity |
|----------|---------|--------------|------------------|
| STAKEHOLDER COMMUNICATION | Executive updates, board communications | Restricted (role-based) | HIGH |
| ENGINEERING | Technical work, code reviews, architecture | Internal team only | MEDIUM |
| PRODUCT & DESIGN | Product planning, feature discussions | Internal team only | MEDIUM |
| MARKETING | Marketing campaigns, positioning | Internal team + marketing | LOW-MEDIUM |
| ADMIN | Server administration, security | Admins only | HIGH |
| PUBLIC | General chat, non-sensitive discussions | All authenticated users | LOW |

---

## Channel Access Controls

### #exec-summary (Executive Summary Channel)

**Purpose**: Centralized channel for stakeholder communications, weekly digests, and executive updates.

**Access Policy**:
- **Read Access**: Executives, leadership, product managers, all team members
- **Write Access**: Bot only (automated summaries)
- **Thread Creation**: Bot only
- **Thread Replies**: All team members (for questions and discussions)

**Sensitivity**: HIGH - Contains strategic information, business metrics, roadmap details

**Permissions Matrix**:

| Role | View Channel | Read Messages | Send Messages | Create Threads | Reply to Threads | Add Reactions | Manage Threads |
|------|--------------|---------------|---------------|----------------|------------------|---------------|----------------|
| Admin | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Leadership | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ❌ |
| Product Manager | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |
| Developer | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ❌ |
| Marketing | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ❌ |
| Guest | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Bot | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

**Rationale**:
- Bot-only posting prevents unauthorized information disclosure
- All team members can read to stay informed
- Thread replies enable Q&A without cluttering main channel
- Product manager can manage threads for moderation

### #engineering (Engineering Channel)

**Purpose**: Technical discussions, code reviews, architecture decisions, sprint planning.

**Access Policy**:
- **Read Access**: Developers, admins
- **Write Access**: Developers, admins
- **Thread Creation**: Developers, admins
- **Bot Notifications**: Linear issue updates, GitHub PR notifications

**Sensitivity**: MEDIUM - Contains technical implementation details, not business strategy

**Permissions Matrix**:

| Role | View Channel | Read Messages | Send Messages | Create Threads | Add Reactions | Manage Messages |
|------|--------------|---------------|---------------|----------------|---------------|-----------------|
| Admin | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Developer | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| Product Manager | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| Leadership | ✅ (optional) | ✅ (optional) | ❌ | ❌ | ✅ | ❌ |
| Marketing | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Guest | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

### #product (Product Channel)

**Purpose**: Product discussions, feature planning, user feedback analysis.

**Access Policy**:
- **Read Access**: Product team, developers, leadership
- **Write Access**: Product team, developers
- **Thread Creation**: Product team, developers

**Sensitivity**: MEDIUM - Contains product strategy, user feedback, feature roadmap

### #marketing (Marketing Channel)

**Purpose**: Marketing campaigns, positioning, competitive analysis, blog content.

**Access Policy**:
- **Read Access**: Marketing team, leadership, product team
- **Write Access**: Marketing team
- **Thread Creation**: Marketing team

**Sensitivity**: MEDIUM - Contains marketing strategy, campaign plans, messaging

### #admin-only (Administration Channel)

**Purpose**: Server administration, permission changes, security incidents, bot configuration.

**Access Policy**:
- **Read Access**: Admins only
- **Write Access**: Admins only
- **Bot Notifications**: Security alerts, audit log summaries

**Sensitivity**: HIGH - Contains administrative actions, security events

**Permissions Matrix**:

| Role | View Channel | Read Messages | Send Messages | All Permissions |
|------|--------------|---------------|---------------|-----------------|
| Admin | ✅ | ✅ | ✅ | ✅ |
| All Others | ❌ | ❌ | ❌ | ❌ |

### #security-alerts (Security Monitoring Channel)

**Purpose**: Real-time security alerts, failed authentication attempts, suspicious activity.

**Access Policy**:
- **Read Access**: Admins only
- **Write Access**: Bot only (automated security alerts)

**Sensitivity**: HIGH - Contains security event data

### #general (Public Channel)

**Purpose**: General team chat, non-sensitive discussions, casual communication.

**Access Policy**:
- **Read Access**: All authenticated users
- **Write Access**: All authenticated users
- **Thread Creation**: All authenticated users

**Sensitivity**: LOW - Public information only

---

## Role Definitions and Permissions

### Discord Role Hierarchy

The following roles are defined in the Discord server, ordered by permission level (highest to lowest):

#### 1. Admin

**Description**: Full server administration and security management

**Assigned To**:
- Server owner
- Infrastructure lead
- Security lead

**Permissions**:
- ✅ All Discord server permissions
- ✅ Access to all channels (including #admin-only, #security-alerts)
- ✅ Manage roles and permissions
- ✅ Manage channels and categories
- ✅ View audit logs
- ✅ Kick/ban users
- ✅ Manage webhooks and bots
- ✅ Override all channel restrictions

**Security Controls**:
- MFA required (enforced in bot commands via HIGH-005)
- Admin role grant requires approval workflow (HIGH-005)
- All admin actions logged to database audit trail (HIGH-005)

**Database Role**: `admin` (highest privilege)

#### 2. Leadership

**Description**: Executive team members (COO, Head of BD, C-suite)

**Assigned To**:
- Chief Operating Officer (COO)
- Head of Business Development
- CEO, CTO, CFO

**Permissions**:
- ✅ View #exec-summary (read-only)
- ✅ Reply to threads in #exec-summary
- ✅ Add reactions (for approval workflow)
- ✅ View #general
- ✅ (Optional) View #engineering, #product (read-only)
- ❌ Send messages in #exec-summary main channel
- ❌ Access #admin-only channels

**Security Controls**:
- Role grant requires admin approval (HIGH-005)
- MFA recommended (not required)
- All permission checks logged to audit trail (HIGH-005)

**Database Role**: `leadership` (mapped internally, may not be in user_roles table)

#### 3. Product Manager

**Description**: Product management team

**Assigned To**:
- Product managers
- Technical product managers

**Permissions**:
- ✅ View and read #exec-summary
- ✅ Reply to threads in #exec-summary
- ✅ Manage threads in #exec-summary (approve with ✅ reaction)
- ✅ Full access to #product
- ✅ Full access to #engineering
- ✅ View #marketing (read-only)
- ✅ View #general

**Security Controls**:
- Role grant requires admin approval (HIGH-005)
- MFA required for approval actions (checking ✅ reactions on summaries)
- All permission checks logged to audit trail (HIGH-005)

**Database Role**: `product_manager` (mapped internally)

#### 4. Developer

**Description**: Engineering team members

**Assigned To**:
- Software engineers
- DevOps engineers
- QA engineers
- Technical leads

**Permissions**:
- ✅ Full access to #engineering
- ✅ View #exec-summary (read-only)
- ✅ Reply to threads in #exec-summary
- ✅ View #product (read-only or full, depending on sub-role)
- ✅ View #sprint-updates
- ✅ View #general
- ❌ Access #admin-only channels

**Security Controls**:
- Role grant requires admin approval (HIGH-005)
- MFA required for sensitive bot commands (`/config`, `/manage-roles`)
- All permission checks logged to audit trail (HIGH-005)

**Database Role**: `developer`

#### 5. Marketing

**Description**: Marketing team members

**Assigned To**:
- Marketing managers
- Content creators
- Developer relations (DevRel)

**Permissions**:
- ✅ Full access to #marketing
- ✅ View #exec-summary (read-only)
- ✅ Reply to threads in #exec-summary
- ✅ View #general
- ❌ Access #engineering, #product, #admin-only

**Security Controls**:
- Role grant requires admin approval (HIGH-005)
- All permission checks logged to audit trail (HIGH-005)

**Database Role**: `marketing` (mapped internally, may not be in user_roles table)

#### 6. Guest

**Description**: Default role for new users

**Assigned To**:
- New team members (before onboarding)
- Temporary contractors
- Users without assigned department

**Permissions**:
- ✅ View #general (read-only)
- ✅ View #help (read-only)
- ❌ Access any other channels
- ❌ Send messages in any channel

**Security Controls**:
- Automatically assigned to all new users (HIGH-005)
- Cannot be manually granted (system-managed)
- All users start as guest, must request role grants

**Database Role**: `guest` (default role)

### Role Mapping (Discord ↔ Database)

The bot uses a **database-first authorization model** implemented in HIGH-005. Discord roles are **informational only** and do not grant permissions directly.

**Authorization Flow**:
1. User executes Discord command
2. Bot queries database for user's roles (via `user_roles` table)
3. Permission check against required role (via `role_verifier` service)
4. If MFA required, prompt for TOTP verification
5. Execute command if authorized
6. Log to `auth_audit_log` table

**Role Grant Workflow** (HIGH-005):
1. User requests role grant via `/role-request <role> <reason>`
2. Request stored in `role_approvals` table with status `pending`
3. Admin reviews pending approvals (future: `/role-approvals` command)
4. Admin approves or rejects (future: `/role-approve <id>`, `/role-reject <id>`)
5. On approval: role granted in `user_roles` table (immutable append-only audit trail)
6. Discord role updated (if applicable)

**Key Security Properties**:
- Immutable audit trail (cannot delete or modify past role grants)
- Admin approval required for all role grants
- MFA required for sensitive operations
- Complete authorization history in database

---

## Bot Permissions

### Discord Bot Account: `agentic-base-bot`

**Bot Token Storage**: Environment variable `DISCORD_BOT_TOKEN` (secured per CRITICAL-003)

**Bot Permissions (Minimum Required)**:

| Permission | Required? | Purpose |
|------------|-----------|---------|
| View Channels | ✅ Yes | Read channel list, detect channel changes |
| Read Messages | ✅ Yes | Read commands, monitor reactions for approval workflow |
| Send Messages | ✅ Yes | Post summaries, respond to commands |
| Create Public Threads | ✅ Yes | Create threads for weekly digests |
| Send Messages in Threads | ✅ Yes | Reply to questions in digest threads |
| Add Reactions | ✅ Yes | Add reaction options for approval workflow |
| Read Message History | ✅ Yes | Implement message retention policy (90-day auto-delete) |
| Manage Messages | ✅ Yes (limited) | Delete messages older than 90 days (retention policy) |
| Manage Threads | ❌ No | Not required (admins manage threads manually) |
| Manage Channels | ❌ No | Not required (admins manage channels manually) |
| Manage Roles | ❌ No | Security risk - roles managed manually by admins |
| Administrator | ❌ No | Security risk - excessive privilege |

**Channel Restrictions**:

The bot has access to the following channels only:

| Channel | Read | Write | Purpose |
|---------|------|-------|---------|
| #exec-summary | ✅ | ✅ | Post weekly digests, respond to `/generate-summary` |
| #engineering | ✅ | ✅ | Respond to bot commands, Linear notifications |
| #product | ✅ | ✅ | Respond to bot commands |
| #marketing | ✅ | ✅ | Respond to bot commands |
| #sprint-updates | ✅ | ✅ | Post automated sprint status updates |
| #linear-notifications | ✅ | ✅ | Post Linear webhook notifications |
| #security-alerts | ❌ | ✅ | Post security alerts (write-only) |
| #admin-only | ❌ | ❌ | No bot access (admin channel) |
| #general | ✅ | ✅ | Respond to help commands |

**Bot Commands Security**:

All bot commands implement the following security controls:

1. **Authentication**: User must be in Discord server and authenticated
2. **Authorization**: Database-first role check via `roleVerifier.hasPermission()` (HIGH-005)
3. **Rate Limiting**: 5 commands per minute per user (HIGH-003)
4. **Input Validation**: Command parameters validated for length and format (HIGH-003)
5. **Audit Logging**: All commands logged to `auth_audit_log` table (HIGH-005)
6. **MFA Verification**: Sensitive commands require MFA (`/config`, `/manage-roles`) (HIGH-005)
7. **Error Handling**: Errors sanitized, no sensitive data in error messages

**Bot Command Categories**:

| Command | Required Role | MFA Required? | Description |
|---------|---------------|---------------|-------------|
| `/help` | guest | ❌ | Show available commands |
| `/show-sprint` | guest | ❌ | Display sprint status |
| `/my-tasks` | developer | ❌ | Show user's Linear tasks |
| `/my-notifications` | guest | ❌ | View notification preferences |
| `/doc <type>` | guest | ❌ | Fetch project documentation |
| `/preview <issue-id>` | developer | ❌ | Get Vercel preview URL |
| `/translate <docs>` | developer | ❌ | Generate DevRel translation (CRITICAL-001, CRITICAL-002) |
| `/mfa-enroll` | guest | ❌ | Enable multi-factor authentication |
| `/mfa-verify <code>` | guest | ❌ | Verify TOTP code |
| `/mfa-status` | guest | ❌ | Check MFA enrollment status |
| `/mfa-disable <code>` | guest | ✅ | Disable MFA (requires verification) |
| `/config` | admin | ✅ | Modify bot configuration (future) |
| `/manage-roles` | admin | ✅ | Manage user roles (future) |
| `/role-approvals` | admin | ✅ | View pending role requests (future) |
| `/role-approve <id>` | admin | ✅ | Approve role grant (future) |
| `/role-reject <id>` | admin | ✅ | Reject role grant (future) |

**Security Notes**:
- Bot token rotated every 90 days (CRITICAL-003)
- Bot runs with least privilege (no unnecessary permissions)
- Bot cannot grant roles or modify permissions (requires admin manual action)
- All bot actions logged to `auth_audit_log` and `logs/` directory

---

## Message Retention Policy

### Overview

To comply with data privacy regulations (GDPR, CCPA) and minimize data exposure, messages in Discord channels are automatically deleted after **90 days** unless explicitly archived.

### Policy Details

**Retention Period**: 90 days from message creation timestamp

**Scope**:
- All channels except #admin-only and #security-alerts
- Includes messages, threads, and attachments
- Applies to both user messages and bot messages

**Exceptions**:
1. **#admin-only**: 1 year retention (administrative record-keeping)
2. **#security-alerts**: 1 year retention (security incident investigation)
3. **Pinned messages**: Exempt from auto-deletion (manually reviewed quarterly)
4. **Archived threads**: Threads marked as "archived" by admins are exempt

### Implementation

**Method**: Automated cron job running daily at 2:00 AM UTC

**Script**: `src/cron/message-retention.ts` (to be implemented)

**Process**:
1. Query Discord API for all messages older than 90 days
2. Filter by channel (skip #admin-only, #security-alerts)
3. Skip pinned messages
4. Skip archived threads
5. Delete messages in batches (avoid rate limits)
6. Log deleted message count to audit log

**Rate Limiting**:
- Discord API rate limit: 50 delete requests per second
- Batch size: 100 messages per API call (bulk delete)
- Sleep 1 second between batches

**Logging**:
```typescript
// Example audit log entry
{
  timestamp: "2025-12-08T02:00:00Z",
  action: "message_retention_cleanup",
  channel: "exec-summary",
  messages_deleted: 342,
  oldest_message_date: "2025-09-08T00:00:00Z",
  status: "success"
}
```

### Notification

**Weekly Summary**: Every Monday, post summary to #admin-only:
```
📊 Message Retention Report - Week of Dec 8, 2025

Messages deleted (90-day policy):
- #exec-summary: 120 messages
- #engineering: 450 messages
- #product: 85 messages
- #marketing: 67 messages
- #general: 234 messages

Total deleted: 956 messages
Next cleanup: December 9, 2025 at 2:00 AM UTC
```

### Manual Override

Admins can exempt specific messages from deletion:

**Pin Message**: Right-click message → "Pin Message" (requires admin permission)

**Archive Thread**: Right-click thread → "Archive Thread" (requires admin permission)

**Bulk Export** (before deletion):
```bash
# Export channel history before retention cleanup
npm run export-channel -- --channel=exec-summary --before-date=2025-09-08 --output=archive/exec-summary-2025-Q3.json
```

### User Notification

Users are notified 7 days before message deletion:

```
⚠️ Message Retention Notice

Your messages in #exec-summary older than 83 days will be deleted in 7 days (December 15, 2025).

If you need to preserve any messages:
1. Pin important messages (admins only)
2. Archive threads containing critical discussions
3. Export channel history (contact admin)

For questions, see: docs/DISCORD-SECURITY.md#message-retention-policy
```

### Compliance

This policy satisfies:
- **GDPR Article 5(1)(e)**: Data minimization and storage limitation
- **CCPA Section 1798.105**: Right to deletion
- **SOC 2**: Data retention and disposal controls

---

## Quarterly Audit Procedures

### Overview

Security audits are performed **quarterly** (every 3 months) to ensure Discord permissions, roles, and bot configuration remain secure and aligned with team structure.

### Audit Schedule

| Quarter | Audit Period | Audit Deadline | Responsible Team |
|---------|--------------|----------------|------------------|
| Q1 | Jan 1 - Mar 31 | April 7 | Security Lead |
| Q2 | Apr 1 - Jun 30 | July 7 | Security Lead |
| Q3 | Jul 1 - Sep 30 | October 7 | Security Lead |
| Q4 | Oct 1 - Dec 31 | January 7 | Security Lead |

### Audit Checklist

#### 1. User Access Review

**Objective**: Verify all Discord users have appropriate role assignments based on current employment status and department.

**Steps**:

1. **Export Current User List**:
   ```bash
   # Run from integration/ directory
   npm run audit-discord-users
   ```

   Output: `audits/discord-users-YYYY-MM-DD.json`

   ```json
   [
     {
       "discordUserId": "123456789",
       "discordUsername": "alice#1234",
       "discordRoles": ["Developer", "Product Manager"],
       "databaseRoles": ["developer"],
       "joinedAt": "2025-01-15T10:00:00Z",
       "lastActive": "2025-12-07T16:30:00Z"
     },
     ...
   ]
   ```

2. **Cross-Reference with HR System**:
   - Compare Discord user list with employee roster
   - Identify users who have left the organization
   - Identify users with role mismatches (Discord ≠ database)

3. **Review Inactive Users**:
   - Flag users with no activity in 90+ days
   - Determine if inactive users should be removed or archived

4. **Remove Departed Users**:
   ```bash
   # For each departed user
   # 1. Kick from Discord server (manual or via bot)
   # 2. Revoke database roles
   npm run revoke-user-roles -- --discord-id=123456789 --reason="User departed company"
   ```

5. **Document Findings**:
   - Users removed: `<list>`
   - Role mismatches corrected: `<list>`
   - Inactive users reviewed: `<list>`

#### 2. Role Permission Audit

**Objective**: Verify role permissions match documented access control policies.

**Steps**:

1. **Export Discord Role Configuration**:
   - Discord Server Settings → Roles
   - Screenshot each role's permissions
   - Export to `audits/discord-roles-YYYY-MM-DD/`

2. **Compare Against Policy** (this document):
   - Cross-reference actual permissions with [Role Definitions and Permissions](#role-definitions-and-permissions)
   - Identify deviations (e.g., Marketing role has access to #engineering)

3. **Review Channel Overrides**:
   - Check each channel's permission overrides
   - Verify channel-specific permissions match [Channel Access Controls](#channel-access-controls)

4. **Correct Deviations**:
   - Update Discord roles/channels to match documented policy
   - OR update policy document if intentional change

5. **Document Findings**:
   - Permission mismatches found: `<list>`
   - Channels with incorrect overrides: `<list>`
   - Corrective actions taken: `<list>`

#### 3. Bot Security Audit

**Objective**: Verify bot permissions, token security, and command authorization.

**Steps**:

1. **Review Bot Permissions**:
   - Discord Server Settings → Integrations → Bots → `agentic-base-bot`
   - Verify bot has only required permissions (see [Bot Permissions](#bot-permissions))
   - Remove any excessive permissions

2. **Token Rotation Check**:
   - Verify bot token was rotated in the last 90 days
   - If >90 days: rotate token immediately
   ```bash
   # Generate new bot token in Discord Developer Portal
   # Update DISCORD_BOT_TOKEN in secrets manager
   npm run rotate-discord-token
   ```

3. **Command Authorization Review**:
   - Review `auth_audit_log` table for authorization denials:
   ```sql
   SELECT operation, COUNT(*) as denial_count, user_discord_id
   FROM auth_audit_log
   WHERE granted = 0
     AND timestamp > datetime('now', '-90 days')
   GROUP BY operation, user_discord_id
   ORDER BY denial_count DESC
   LIMIT 20;
   ```
   - Investigate high denial counts (potential privilege escalation attempts)

4. **MFA Enrollment Check** (HIGH-005):
   - Query MFA enrollment rate for admins:
   ```sql
   SELECT
     COUNT(DISTINCT u.id) as total_admins,
     COUNT(DISTINCT m.user_id) as mfa_enrolled,
     ROUND(100.0 * COUNT(DISTINCT m.user_id) / COUNT(DISTINCT u.id), 1) as enrollment_rate
   FROM users u
   LEFT JOIN mfa_enrollments m ON u.id = m.user_id AND m.status = 'active'
   WHERE u.id IN (
     SELECT DISTINCT user_id FROM user_roles WHERE role = 'admin' AND action = 'granted'
   );
   ```
   - Target: 100% admin MFA enrollment
   - If <100%: remind admins to enroll via `/mfa-enroll`

5. **Document Findings**:
   - Bot permissions reviewed: ✅
   - Token rotated: ✅ (date: YYYY-MM-DD)
   - Authorization anomalies: `<list>`
   - MFA enrollment rate: X%

#### 4. Message Retention Compliance

**Objective**: Verify 90-day message retention policy is functioning correctly.

**Steps**:

1. **Check Retention Cron Job**:
   ```bash
   # Verify cron job is running
   npm run check-cron-status
   ```

   Expected output:
   ```
   ✅ Daily message retention job: ACTIVE
   Last run: 2025-12-08T02:00:00Z
   Messages deleted: 956
   Next run: 2025-12-09T02:00:00Z
   ```

2. **Verify Message Age**:
   - Randomly sample 10 messages from each channel
   - Verify no messages older than 90 days (except #admin-only, #security-alerts)
   - Document oldest message found per channel

3. **Review Retention Logs**:
   ```bash
   # View last 90 days of retention cleanup logs
   grep "message_retention_cleanup" logs/audit.log | tail -n 90
   ```

4. **Pinned Message Review**:
   - Review all pinned messages in each channel
   - Verify pinned messages are still relevant
   - Unpin outdated messages (triggers retention policy)

5. **Document Findings**:
   - Retention cron job status: ✅ ACTIVE
   - Oldest message age per channel: `<list>`
   - Pinned messages reviewed: X total, Y unpinned

#### 5. Audit Trail Verification

**Objective**: Verify complete audit trail exists for all permission changes and admin actions.

**Steps**:

1. **Query Audit Logs** (HIGH-005):
   ```sql
   -- All role grants in last 90 days
   SELECT
     ur.id,
     u.discord_username,
     ur.role,
     ur.action,
     ur.granted_by_discord_id,
     ur.reason,
     ur.effective_at
   FROM user_roles ur
   JOIN users u ON ur.user_id = u.id
   WHERE ur.effective_at > datetime('now', '-90 days')
   ORDER BY ur.effective_at DESC;
   ```

2. **Verify All Role Grants Have Approval**:
   ```sql
   -- Find role grants without approval records
   SELECT
     ur.id,
     u.discord_username,
     ur.role,
     ur.granted_by_discord_id,
     ur.effective_at
   FROM user_roles ur
   JOIN users u ON ur.user_id = u.id
   WHERE ur.action = 'granted'
     AND ur.approval_id IS NULL
     AND ur.role != 'guest'
     AND ur.effective_at > datetime('now', '-90 days');
   ```
   - Any results indicate approval workflow bypass (security issue)

3. **Review Failed MFA Attempts**:
   ```sql
   -- Failed MFA verifications in last 90 days
   SELECT
     u.discord_username,
     mc.challenge_type,
     mc.operation,
     mc.failure_reason,
     mc.ip_address,
     mc.challenged_at,
     COUNT(*) as failed_attempts
   FROM mfa_challenges mc
   JOIN users u ON mc.user_id = u.id
   WHERE mc.success = 0
     AND mc.challenged_at > datetime('now', '-90 days')
   GROUP BY u.id, mc.operation
   HAVING failed_attempts >= 5
   ORDER BY failed_attempts DESC;
   ```
   - High failure counts indicate potential brute force attempts

4. **Export Audit Report**:
   ```bash
   npm run export-audit-report -- --start-date=2025-09-08 --end-date=2025-12-08 --output=audits/quarterly-audit-2025-Q4.pdf
   ```

5. **Document Findings**:
   - Role grants without approval: X
   - Failed MFA attempts >5: X users
   - Audit trail completeness: ✅ / ❌

### Audit Report Template

```markdown
# Discord Security Audit Report

**Audit Period**: Q4 2025 (Oct 1 - Dec 31, 2025)
**Audit Date**: January 5, 2026
**Auditor**: [Security Lead Name]
**Status**: ✅ PASSED / ⚠️ ISSUES FOUND / ❌ FAILED

---

## Executive Summary

[Brief summary of findings]

---

## Detailed Findings

### 1. User Access Review

- **Total Users**: X
- **Users Removed**: Y (departed employees)
- **Role Mismatches Corrected**: Z
- **Inactive Users (>90 days)**: W

**Action Items**:
- [ ] Remove user X (departed)
- [ ] Update role for user Y (promotion to admin)

---

### 2. Role Permission Audit

- **Roles Reviewed**: 6 (admin, leadership, product_manager, developer, marketing, guest)
- **Permission Mismatches**: X
- **Channels with Incorrect Overrides**: Y

**Action Items**:
- [ ] Remove Marketing access to #engineering
- [ ] Update #exec-summary to bot-only write

---

### 3. Bot Security Audit

- **Bot Token Last Rotated**: YYYY-MM-DD
- **Bot Permissions**: ✅ Least privilege verified
- **Authorization Denials**: X in last 90 days
- **MFA Enrollment Rate (Admins)**: X%

**Action Items**:
- [ ] Rotate bot token (overdue)
- [ ] Remind admin Y to enroll in MFA

---

### 4. Message Retention Compliance

- **Retention Policy Status**: ✅ ACTIVE
- **Oldest Message Age**: 89 days (#exec-summary)
- **Pinned Messages Reviewed**: X total, Y unpinned

**Action Items**:
- None (policy functioning correctly)

---

### 5. Audit Trail Verification

- **Role Grants (Last 90 Days)**: X
- **Role Grants Without Approval**: Y ⚠️
- **Failed MFA Attempts (>5)**: Z users

**Action Items**:
- [ ] Investigate role grant without approval (user X, role Y)
- [ ] Review failed MFA attempts for user Z (potential attack)

---

## Compliance Status

- [✅] GDPR Article 5(1)(e) - Storage limitation (message retention)
- [✅] SOC 2 - Access control reviews (quarterly audit)
- [⚠️] SOC 2 - Least privilege (bot has excess permissions)

---

## Recommendations

1. Rotate bot token immediately (overdue by 15 days)
2. Enforce 100% MFA enrollment for admins
3. Investigate role grant approval bypass for user X

---

## Sign-Off

**Auditor**: [Name], [Title]
**Date**: YYYY-MM-DD

**Reviewed By**: [Admin Name], [Title]
**Date**: YYYY-MM-DD
```

### Audit Tracking

All quarterly audit reports are stored in:
- **File System**: `audits/quarterly-YYYY-QX.md`
- **Google Drive**: Shared with leadership and security team
- **Audit Log Database**: Summary stored in `auth_audit_log` table

---

## Security Best Practices

### For Admins

1. **Principle of Least Privilege**:
   - Only grant roles users need for their job function
   - Use guest role for new hires until onboarding complete
   - Revoke roles immediately when users change roles or depart

2. **MFA Enforcement**:
   - Require all admins to enroll in MFA (via `/mfa-enroll`)
   - Verify MFA enrollment quarterly
   - Use backup codes for account recovery (store securely)

3. **Token Management**:
   - Rotate bot token every 90 days
   - Never share bot token via Discord or email
   - Store token in environment variables only (see CRITICAL-003)

4. **Permission Reviews**:
   - Review Discord permissions monthly (informal)
   - Conduct formal quarterly audits (documented)
   - Update this document when policies change

5. **Incident Response**:
   - Monitor #security-alerts channel for bot alerts
   - Respond to security incidents within 4 hours
   - Document incidents in `docs/incidents/`

### For All Team Members

1. **Account Security**:
   - Enable Discord 2FA (separate from bot MFA)
   - Use strong, unique password for Discord
   - Never share credentials or bot commands

2. **Channel Discipline**:
   - Post sensitive information only in appropriate channels
   - Do not discuss business strategy in #general
   - Use #exec-summary threads for questions, not DMs

3. **Bot Commands**:
   - Use `/help` to see available commands
   - Report bot errors to #help channel
   - Do not attempt to exploit or bypass bot permissions

4. **Message Sensitivity**:
   - Assume all Discord messages are logged
   - Do not post credentials, API keys, or secrets
   - Messages auto-delete after 90 days (retention policy)

5. **Reporting Issues**:
   - Report suspicious activity to admins immediately
   - Report unauthorized access attempts
   - Report bot malfunctions or permission errors

---

## Incident Response

### Security Incident Classification

| Severity | Definition | Examples | Response Time |
|----------|------------|----------|---------------|
| CRITICAL | Unauthorized access to admin channels or bot token compromise | Bot token leaked, admin account compromised | Immediate (< 1 hour) |
| HIGH | Unauthorized role escalation or permission bypass | User grants themselves admin role, MFA bypass | 4 hours |
| MEDIUM | Authorization denial pattern or suspicious activity | Repeated failed MFA attempts, command abuse | 24 hours |
| LOW | Policy violation or misconfiguration | User posts in wrong channel, minor permission error | 1 week |

### Incident Response Playbook

#### 1. Bot Token Compromise (CRITICAL)

**Indicators**:
- Bot token appears in public repository
- Unauthorized bot actions (messages, role changes)
- Alerts from secret scanning tools

**Response Steps**:
1. **Immediately rotate bot token** (Discord Developer Portal → Bot → Reset Token)
2. **Update environment variables** with new token:
   ```bash
   # Update secrets manager
   npm run rotate-discord-token -- --new-token=NEW_TOKEN_HERE
   ```
3. **Restart bot** to pick up new token:
   ```bash
   npm run bot:restart
   ```
4. **Audit bot actions** in last 24 hours:
   ```sql
   SELECT * FROM auth_audit_log
   WHERE timestamp > datetime('now', '-1 day')
   ORDER BY timestamp DESC;
   ```
5. **Review Discord audit log** (Server Settings → Audit Log)
6. **Notify team** in #admin-only channel
7. **Document incident** in `docs/incidents/YYYY-MM-DD-bot-token-compromise.md`

**Post-Incident**:
- Review how token was leaked (code commit, log file, etc.)
- Implement controls to prevent recurrence
- Update secrets rotation policy if needed

#### 2. Unauthorized Role Escalation (HIGH)

**Indicators**:
- User has role they shouldn't (detected in audit)
- Alert from `auth_audit_log` (role grant without approval)
- User reports unexpected permissions

**Response Steps**:
1. **Verify unauthorized role grant**:
   ```sql
   SELECT * FROM user_roles
   WHERE user_id = <USER_ID> AND role = '<ROLE>'
   ORDER BY effective_at DESC LIMIT 1;
   ```
2. **Revoke unauthorized role**:
   ```bash
   npm run revoke-user-roles -- --discord-id=<USER_ID> --role=<ROLE> --reason="Unauthorized escalation"
   ```
3. **Investigate root cause**:
   - Check who granted the role (`granted_by_discord_id`)
   - Review approval workflow (was approval bypassed?)
   - Check for bot vulnerabilities or permission bugs
4. **Audit user's actions** while role was active:
   ```sql
   SELECT * FROM auth_audit_log
   WHERE user_discord_id = '<USER_ID>'
     AND timestamp BETWEEN '<ESCALATION_TIME>' AND '<NOW>'
   ORDER BY timestamp DESC;
   ```
5. **Notify admins** in #admin-only channel
6. **Document incident**

**Post-Incident**:
- Fix approval workflow if bypassed
- Review role grant code for vulnerabilities
- Implement additional monitoring/alerting

#### 3. MFA Brute Force Attempt (MEDIUM)

**Indicators**:
- User has >10 failed MFA attempts in 24 hours
- Alert from MFA rate limiting system

**Response Steps**:
1. **Query failed MFA attempts**:
   ```sql
   SELECT * FROM mfa_challenges
   WHERE user_id = <USER_ID>
     AND success = 0
     AND challenged_at > datetime('now', '-1 day')
   ORDER BY challenged_at DESC;
   ```
2. **Contact user** to verify legitimate access attempts
3. **If user confirms attack**:
   - Temporarily disable user account
   - Reset MFA enrollment (user must re-enroll)
   - Check for account compromise indicators
4. **If user denies attempts**:
   - Assume account compromise
   - Force password reset
   - Revoke all active sessions
   - Require MFA re-enrollment
5. **Document incident**

**Post-Incident**:
- Review MFA rate limiting effectiveness
- Consider additional security controls (IP geolocation, anomaly detection)

#### 4. Message Retention Failure (MEDIUM)

**Indicators**:
- Messages older than 90 days found in channel
- Retention cron job failed
- Alert from monitoring system

**Response Steps**:
1. **Check cron job status**:
   ```bash
   npm run check-cron-status
   ```
2. **Review error logs**:
   ```bash
   grep "message_retention" logs/error.log | tail -n 50
   ```
3. **Manually trigger retention cleanup**:
   ```bash
   npm run message-retention -- --force --channel=<CHANNEL>
   ```
4. **Verify cleanup succeeded**:
   - Sample messages from channel
   - Verify no messages >90 days old
5. **Fix cron job** if misconfigured
6. **Document incident**

**Post-Incident**:
- Set up monitoring/alerting for retention cron job
- Review retention policy effectiveness

---

## Compliance Requirements

### GDPR (General Data Protection Regulation)

**Applicable Articles**:
- **Article 5(1)(e)**: Storage limitation - Data kept only as long as necessary
- **Article 17**: Right to erasure - Users can request data deletion
- **Article 25**: Data protection by design and default

**Compliance Measures**:
1. **90-Day Message Retention**: Automatically delete messages after 90 days (storage limitation)
2. **User Data Export**: Users can request export of their Discord data
   ```bash
   npm run export-user-data -- --discord-id=<USER_ID> --output=exports/user-<ID>.json
   ```
3. **Right to Erasure**: Users can request deletion of their data
   ```bash
   npm run delete-user-data -- --discord-id=<USER_ID> --confirm
   ```
4. **Data Minimization**: Collect only necessary data (Discord ID, username, roles)
5. **Purpose Limitation**: Data used only for team communication and access control

### SOC 2 (System and Organization Controls 2)

**Applicable Trust Service Criteria**:
- **CC6.1**: Logical and physical access controls
- **CC6.2**: Prior to issuing system credentials and granting system access, the entity registers and authorizes new internal and external users
- **CC6.3**: The entity authorizes, modifies, or removes access to data, software, functions, and other protected information assets

**Compliance Measures**:
1. **Role-Based Access Control (RBAC)**: All channels have defined role permissions
2. **Access Reviews**: Quarterly audits of user access and permissions
3. **Least Privilege**: Users granted minimum permissions needed for job function
4. **Audit Trail**: Complete log of permission changes in `auth_audit_log` table
5. **MFA for Admins**: Multi-factor authentication required for sensitive operations

### CCPA (California Consumer Privacy Act)

**Applicable Sections**:
- **Section 1798.105**: Right to deletion
- **Section 1798.110**: Right to know what data is collected

**Compliance Measures**:
1. **Data Disclosure**: Users informed of data collection (this document)
2. **Right to Deletion**: Users can request data deletion (same as GDPR)
3. **Data Export**: Users can request export of their data (same as GDPR)

---

## Document Maintenance

### Review Schedule

- **Quarterly**: Full security audit and policy review
- **Annually**: Comprehensive policy update and leadership approval

### Change Log

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-12-08 | Security Team | Initial version (HIGH-001 implementation) |

### Approval

**Approved By**: [Security Lead Name]
**Date**: 2025-12-08
**Next Review**: 2026-03-08 (Q1 2026 Audit)

---

## Related Documents

- **HIGH-005 Implementation**: Database-backed authorization and MFA (`docs/HIGH-005-IMPLEMENTATION.md`)
- **HIGH-003 Implementation**: Rate limiting and DoS prevention (`docs/HIGH-003-IMPLEMENTATION.md`)
- **CRITICAL-003**: Secrets management (`docs/audits/2025-12-08/CRITICAL-003-REMEDIATION.md`)
- **Team Playbook**: User guide for Discord integration (`docs/team-playbook.md`)
- **DevRel Integration Architecture**: System architecture (`docs/devrel-integration-architecture.md`)

---

**Document Version**: 1.0
**Last Updated**: December 8, 2025
**Maintained By**: Security Team
**Contact**: security@agentic-base.com
