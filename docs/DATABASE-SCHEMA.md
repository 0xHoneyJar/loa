# Database Schema for User Role Management

**Purpose**: Implement HIGH-005 (Department Detection Security Hardening) with immutable user-to-role mappings, audit trail, and MFA support.

## Overview

This schema provides:
- **Immutable user role mappings** (audit trail of all role changes)
- **MFA enrollment and verification** for sensitive operations
- **Admin approval workflow** for role grants
- **Department/team assignments** for access control
- **Complete audit logging** of all authorization events

## Database Technology

**SQLite** (embedded database)
- **Pros**: Simple deployment, no external database server needed, ACID compliance, sufficient for auth use case
- **Cons**: Not suitable for multi-instance deployments (use PostgreSQL for production scale-out)
- **File**: `integration/data/auth.db`

## Tables

### 1. `users` - User Identity Registry

Immutable registry of all users who have interacted with the system.

```sql
CREATE TABLE users (
  -- Primary Key
  id INTEGER PRIMARY KEY AUTOINCREMENT,

  -- Discord Identity
  discord_user_id TEXT NOT NULL UNIQUE,
  discord_username TEXT NOT NULL,
  discord_discriminator TEXT,

  -- Linear Identity (optional)
  linear_user_id TEXT UNIQUE,
  linear_email TEXT,

  -- Department/Team Assignment
  department TEXT,  -- engineering, product, exec, finance, marketing, etc.
  team TEXT,        -- frontend, backend, devops, etc.

  -- Status
  status TEXT NOT NULL DEFAULT 'active',  -- active, suspended, deactivated

  -- Metadata
  first_seen_at TEXT NOT NULL,  -- ISO 8601 timestamp
  last_seen_at TEXT NOT NULL,   -- ISO 8601 timestamp
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,

  -- Constraints
  CHECK (status IN ('active', 'suspended', 'deactivated'))
);

CREATE INDEX idx_users_discord_id ON users(discord_user_id);
CREATE INDEX idx_users_status ON users(status);
CREATE INDEX idx_users_department ON users(department);
```

**Example**:
```sql
INSERT INTO users (discord_user_id, discord_username, department, team, status, first_seen_at, last_seen_at, created_at, updated_at)
VALUES ('123456789012345678', 'alice#1234', 'engineering', 'backend', 'active', '2025-12-08T10:00:00Z', '2025-12-08T10:00:00Z', '2025-12-08T10:00:00Z', '2025-12-08T10:00:00Z');
```

---

### 2. `user_roles` - Role Assignments (Immutable Audit Trail)

Immutable log of all role assignments and revocations. Never updated or deleted.

```sql
CREATE TABLE user_roles (
  -- Primary Key
  id INTEGER PRIMARY KEY AUTOINCREMENT,

  -- Foreign Key to users table
  user_id INTEGER NOT NULL,

  -- Role Assignment
  role TEXT NOT NULL,  -- admin, developer, researcher, guest
  action TEXT NOT NULL,  -- granted, revoked

  -- Authorization Context
  granted_by_user_id INTEGER,  -- Foreign key to users table (who granted this role)
  granted_by_discord_id TEXT,  -- Discord ID of grantor (for audit)
  approval_id INTEGER,  -- Foreign key to role_approvals table (if approval was required)

  -- Reason and Context
  reason TEXT,  -- Why was this role granted/revoked?
  metadata TEXT,  -- JSON blob for additional context

  -- Timestamps
  effective_at TEXT NOT NULL,  -- When this role takes effect (ISO 8601)
  expires_at TEXT,  -- Optional expiration (ISO 8601)
  created_at TEXT NOT NULL,

  -- Constraints
  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (granted_by_user_id) REFERENCES users(id),
  FOREIGN KEY (approval_id) REFERENCES role_approvals(id),
  CHECK (role IN ('admin', 'developer', 'researcher', 'guest')),
  CHECK (action IN ('granted', 'revoked'))
);

CREATE INDEX idx_user_roles_user_id ON user_roles(user_id);
CREATE INDEX idx_user_roles_role ON user_roles(role);
CREATE INDEX idx_user_roles_action ON user_roles(action);
CREATE INDEX idx_user_roles_effective_at ON user_roles(effective_at);
```

**Querying Active Roles**:
```sql
-- Get user's current active roles
SELECT DISTINCT role
FROM user_roles ur
WHERE ur.user_id = ?
  AND ur.effective_at <= datetime('now')
  AND (ur.expires_at IS NULL OR ur.expires_at > datetime('now'))
  AND ur.action = 'granted'
  AND ur.role NOT IN (
    -- Exclude roles that have been revoked after this grant
    SELECT role FROM user_roles
    WHERE user_id = ur.user_id
      AND role = ur.role
      AND action = 'revoked'
      AND effective_at > ur.effective_at
  );
```

**Example**:
```sql
-- Grant developer role to Alice (approved immediately by admin Bob)
INSERT INTO user_roles (user_id, role, action, granted_by_user_id, granted_by_discord_id, reason, effective_at, created_at)
VALUES (1, 'developer', 'granted', 2, '987654321098765432', 'New hire onboarding', '2025-12-08T10:00:00Z', '2025-12-08T10:00:00Z');

-- Revoke developer role from Alice (1 month later)
INSERT INTO user_roles (user_id, role, action, granted_by_user_id, granted_by_discord_id, reason, effective_at, created_at)
VALUES (1, 'developer', 'revoked', 2, '987654321098765432', 'Team transition', '2025-01-08T10:00:00Z', '2025-01-08T10:00:00Z');
```

---

### 3. `role_approvals` - Admin Approval Workflow

Pending and completed role grant approvals.

```sql
CREATE TABLE role_approvals (
  -- Primary Key
  id INTEGER PRIMARY KEY AUTOINCREMENT,

  -- Request Details
  requested_user_id INTEGER NOT NULL,  -- User requesting the role
  requested_role TEXT NOT NULL,
  requested_department TEXT,  -- Optional department restriction

  -- Requester Info
  requester_discord_id TEXT NOT NULL,
  requester_username TEXT NOT NULL,

  -- Approval Status
  status TEXT NOT NULL DEFAULT 'pending',  -- pending, approved, rejected, expired

  -- Approver Info (when approved/rejected)
  approver_user_id INTEGER,
  approver_discord_id TEXT,
  approval_reason TEXT,

  -- Timestamps
  requested_at TEXT NOT NULL,
  reviewed_at TEXT,  -- When approval decision was made
  expires_at TEXT NOT NULL,  -- Request expires after 7 days

  -- Constraints
  FOREIGN KEY (requested_user_id) REFERENCES users(id),
  FOREIGN KEY (approver_user_id) REFERENCES users(id),
  CHECK (status IN ('pending', 'approved', 'rejected', 'expired')),
  CHECK (requested_role IN ('admin', 'developer', 'researcher'))
);

CREATE INDEX idx_role_approvals_status ON role_approvals(status);
CREATE INDEX idx_role_approvals_requested_user ON role_approvals(requested_user_id);
CREATE INDEX idx_role_approvals_expires_at ON role_approvals(expires_at);
```

**Example**:
```sql
-- Alice requests developer role
INSERT INTO role_approvals (requested_user_id, requested_role, requester_discord_id, requester_username, status, requested_at, expires_at)
VALUES (1, 'developer', '123456789012345678', 'alice#1234', 'pending', '2025-12-08T10:00:00Z', '2025-12-15T10:00:00Z');

-- Admin Bob approves it
UPDATE role_approvals
SET status = 'approved', approver_user_id = 2, approver_discord_id = '987654321098765432', approval_reason = 'Verified credentials', reviewed_at = '2025-12-08T11:00:00Z'
WHERE id = 1;
```

---

### 4. `mfa_enrollments` - Multi-Factor Authentication

MFA enrollment status and secrets for users.

```sql
CREATE TABLE mfa_enrollments (
  -- Primary Key
  id INTEGER PRIMARY KEY AUTOINCREMENT,

  -- Foreign Key to users table
  user_id INTEGER NOT NULL UNIQUE,

  -- MFA Type
  mfa_type TEXT NOT NULL DEFAULT 'totp',  -- totp (Google Authenticator), sms, email

  -- TOTP Secret (encrypted at rest)
  totp_secret TEXT,  -- Base32-encoded secret
  backup_codes TEXT,  -- JSON array of backup codes (hashed)

  -- Status
  status TEXT NOT NULL DEFAULT 'pending',  -- pending, active, disabled

  -- Verification
  verified_at TEXT,  -- When user verified MFA setup
  last_used_at TEXT,  -- Last successful MFA verification

  -- Metadata
  enrolled_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,

  -- Constraints
  FOREIGN KEY (user_id) REFERENCES users(id),
  CHECK (mfa_type IN ('totp', 'sms', 'email')),
  CHECK (status IN ('pending', 'active', 'disabled'))
);

CREATE INDEX idx_mfa_enrollments_user_id ON mfa_enrollments(user_id);
CREATE INDEX idx_mfa_enrollments_status ON mfa_enrollments(status);
```

**Example**:
```sql
-- Alice enrolls in MFA
INSERT INTO mfa_enrollments (user_id, mfa_type, totp_secret, backup_codes, status, enrolled_at, created_at, updated_at)
VALUES (1, 'totp', 'JBSWY3DPEHPK3PXP', '["code1_hashed", "code2_hashed"]', 'pending', '2025-12-08T10:00:00Z', '2025-12-08T10:00:00Z', '2025-12-08T10:00:00Z');

-- Alice verifies MFA setup
UPDATE mfa_enrollments
SET status = 'active', verified_at = '2025-12-08T10:05:00Z', updated_at = '2025-12-08T10:05:00Z'
WHERE user_id = 1;
```

---

### 5. `mfa_challenges` - MFA Verification Log

Log of all MFA verification attempts (successful and failed).

```sql
CREATE TABLE mfa_challenges (
  -- Primary Key
  id INTEGER PRIMARY KEY AUTOINCREMENT,

  -- Foreign Key to users table
  user_id INTEGER NOT NULL,

  -- Challenge Details
  challenge_type TEXT NOT NULL,  -- totp, backup_code, sms
  operation TEXT NOT NULL,  -- role_grant, sensitive_command, admin_action
  operation_context TEXT,  -- JSON blob with operation details

  -- Verification Result
  success BOOLEAN NOT NULL,
  failure_reason TEXT,  -- Invalid code, expired, rate limited, etc.

  -- Security Context
  ip_address TEXT,
  user_agent TEXT,

  -- Timestamps
  challenged_at TEXT NOT NULL,

  -- Constraints
  FOREIGN KEY (user_id) REFERENCES users(id),
  CHECK (challenge_type IN ('totp', 'backup_code', 'sms', 'email'))
);

CREATE INDEX idx_mfa_challenges_user_id ON mfa_challenges(user_id);
CREATE INDEX idx_mfa_challenges_success ON mfa_challenges(success);
CREATE INDEX idx_mfa_challenges_challenged_at ON mfa_challenges(challenged_at);
```

**Example**:
```sql
-- Alice attempts MFA verification for role grant
INSERT INTO mfa_challenges (user_id, challenge_type, operation, operation_context, success, challenged_at)
VALUES (1, 'totp', 'role_grant', '{"role": "admin", "granted_by": "bob"}', 1, '2025-12-08T10:00:00Z');

-- Failed attempt
INSERT INTO mfa_challenges (user_id, challenge_type, operation, success, failure_reason, challenged_at)
VALUES (1, 'totp', 'sensitive_command', 0, 'Invalid TOTP code', '2025-12-08T10:01:00Z');
```

---

### 6. `auth_audit_log` - Complete Authorization Audit Trail

Comprehensive log of all authorization checks and outcomes.

```sql
CREATE TABLE auth_audit_log (
  -- Primary Key
  id INTEGER PRIMARY KEY AUTOINCREMENT,

  -- User Context
  user_id INTEGER,
  discord_user_id TEXT,
  discord_username TEXT,

  -- Authorization Check
  operation TEXT NOT NULL,  -- command, role_grant, permission_check, etc.
  resource TEXT,  -- What was being accessed?
  required_role TEXT,  -- What role was required?
  required_permission TEXT,  -- What permission was required?

  -- Outcome
  granted BOOLEAN NOT NULL,
  denial_reason TEXT,  -- Why was access denied?

  -- Security Context
  ip_address TEXT,
  user_agent TEXT,
  channel_id TEXT,  -- Discord channel where action occurred
  guild_id TEXT,  -- Discord guild ID

  -- MFA Context
  mfa_required BOOLEAN NOT NULL DEFAULT 0,
  mfa_verified BOOLEAN,

  -- Timestamps
  timestamp TEXT NOT NULL,

  -- Constraints
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX idx_auth_audit_log_user_id ON auth_audit_log(user_id);
CREATE INDEX idx_auth_audit_log_granted ON auth_audit_log(granted);
CREATE INDEX idx_auth_audit_log_timestamp ON auth_audit_log(timestamp);
CREATE INDEX idx_auth_audit_log_operation ON auth_audit_log(operation);
```

**Example**:
```sql
-- Alice attempts to run /translate command (requires developer role)
INSERT INTO auth_audit_log (user_id, discord_user_id, discord_username, operation, resource, required_role, granted, channel_id, guild_id, mfa_required, timestamp)
VALUES (1, '123456789012345678', 'alice#1234', 'translate_command', '/translate', 'developer', 1, '999888777666555444', '111222333444555666', 0, '2025-12-08T10:00:00Z');

-- Bob (guest) attempts to run /translate command (denied)
INSERT INTO auth_audit_log (user_id, discord_user_id, discord_username, operation, resource, required_role, granted, denial_reason, channel_id, guild_id, mfa_required, timestamp)
VALUES (3, '555666777888999000', 'bob#5678', 'translate_command', '/translate', 'developer', 0, 'User has role guest, requires developer', '999888777666555444', '111222333444555666', 0, '2025-12-08T10:01:00Z');
```

---

## Schema Initialization

**File**: `integration/src/database/schema.sql`

```sql
-- Create tables in correct order (respecting foreign keys)
-- 1. users (no dependencies)
-- 2. user_roles (depends on users)
-- 3. role_approvals (depends on users)
-- 4. mfa_enrollments (depends on users)
-- 5. mfa_challenges (depends on users)
-- 6. auth_audit_log (depends on users)

-- Enable foreign key constraints
PRAGMA foreign_keys = ON;

-- ... (all CREATE TABLE statements from above)
```

---

## Migration Strategy

### Phase 1: Backfill Existing Users
1. Scan Discord guild members
2. For each member, create entry in `users` table
3. For each member with Discord roles, create entry in `user_roles` table (action='granted', granted_by=system)

### Phase 2: Switch to Database-First
1. Update `middleware/auth.ts` to query database first
2. Fall back to Discord roles if database entry doesn't exist (for new users)
3. Log warning when falling back to Discord

### Phase 3: MFA Enrollment (Optional)
1. Add `/mfa-enroll` command for users to set up MFA
2. Add `/mfa-verify` command for verification
3. Require MFA for admin role grants

---

## Security Considerations

### 1. Secret Encryption
- **TOTP secrets** in `mfa_enrollments.totp_secret` should be encrypted at rest
- Use `libsodium` or Node's `crypto.subtle` for encryption
- Store encryption key in environment variable `MFA_ENCRYPTION_KEY`

### 2. Backup Codes
- **Backup codes** should be hashed (bcrypt) before storage
- Generate 10 backup codes on enrollment
- Mark as used after verification

### 3. Rate Limiting
- **MFA attempts**: Max 5 failed attempts per 15 minutes
- **Role requests**: Max 3 pending requests per user
- **Audit log queries**: Rate limited to prevent DoS

### 4. Data Retention
- **auth_audit_log**: Retain for 1 year (compliance requirement)
- **mfa_challenges**: Retain for 90 days
- **user_roles**: Never delete (immutable audit trail)

### 5. Access Control
- Database file permissions: `0600` (owner read/write only)
- No direct database access from Discord commands
- All access through `user-mapping-service.ts`

---

## Database Access Layer

**File**: `integration/src/database/db.ts`

```typescript
import sqlite3 from 'sqlite3';
import { open, Database } from 'sqlite';
import path from 'path';
import fs from 'fs';

export class AuthDatabase {
  private db: Database | null = null;

  async initialize(): Promise<void> {
    const dbPath = path.resolve(__dirname, '../../data/auth.db');
    const dbDir = path.dirname(dbPath);

    // Create data directory if it doesn't exist
    if (!fs.existsSync(dbDir)) {
      fs.mkdirSync(dbDir, { recursive: true, mode: 0o700 });
    }

    // Open database
    this.db = await open({
      filename: dbPath,
      driver: sqlite3.Database
    });

    // Enable foreign keys
    await this.db.exec('PRAGMA foreign_keys = ON;');

    // Run schema initialization
    await this.initializeSchema();
  }

  private async initializeSchema(): Promise<void> {
    const schemaPath = path.resolve(__dirname, './schema.sql');
    const schema = fs.readFileSync(schemaPath, 'utf8');
    await this.db!.exec(schema);
  }

  getConnection(): Database {
    if (!this.db) {
      throw new Error('Database not initialized. Call initialize() first.');
    }
    return this.db;
  }
}

export const authDb = new AuthDatabase();
```

---

## API Usage Examples

### User Mapping Service

```typescript
import { UserMappingService } from './services/user-mapping-service';

const userService = new UserMappingService();

// Get user's current roles
const roles = await userService.getUserRoles('123456789012345678');
// Returns: ['developer', 'researcher']

// Grant role with approval
const approval = await userService.requestRoleGrant({
  discordUserId: '123456789012345678',
  role: 'admin',
  reason: 'Promotion to tech lead'
});
// Returns: { approvalId: 1, status: 'pending' }

// Admin approves role grant
await userService.approveRoleGrant(approval.approvalId, {
  approverDiscordId: '987654321098765432',
  reason: 'Verified credentials and need'
});
```

### Role Verification

```typescript
import { RoleVerifier } from './services/role-verifier';

const verifier = new RoleVerifier();

// Check if user has permission
const hasPermission = await verifier.hasPermission(
  '123456789012345678',  // Discord user ID
  'translate',  // Permission required
  {
    command: '/translate',
    channel: '999888777666555444',
    guild: '111222333444555666'
  }
);
// Returns: true or false
```

### MFA Verification

```typescript
import { MfaVerifier } from './services/mfa-verifier';

const mfaVerifier = new MfaVerifier();

// Check if MFA is required for operation
const mfaRequired = await mfaVerifier.isMfaRequired('admin_role_grant');
// Returns: true

// Verify TOTP code
const verified = await mfaVerifier.verifyTotp(
  '123456789012345678',  // Discord user ID
  '123456',  // TOTP code from authenticator app
  { operation: 'admin_role_grant', context: { role: 'admin' } }
);
// Returns: { success: true, challengeId: 42 }
```

---

## Implementation Checklist

- [ ] Create `integration/data/` directory
- [ ] Create `integration/src/database/schema.sql`
- [ ] Create `integration/src/database/db.ts`
- [ ] Implement `user-mapping-service.ts` (CRUD operations)
- [ ] Implement `role-verifier.ts` (permission checks with DB backing)
- [ ] Implement `mfa-verifier.ts` (TOTP enrollment and verification)
- [ ] Update `middleware/auth.ts` to use database-first approach
- [ ] Create migration script to backfill existing users
- [ ] Add `/mfa-enroll` and `/mfa-verify` Discord commands
- [ ] Add `/role-request` Discord command for self-service role requests
- [ ] Add admin dashboard for role approvals
- [ ] Write comprehensive tests (unit + integration)
- [ ] Document security best practices

---

**Implementation Status**: ⏳ Pending
**Security Impact**: Prevents role spoofing, provides immutable audit trail, adds MFA for sensitive operations
**Compliance**: Supports SOC2, GDPR, and ISO 27001 requirements for access control and audit logging
