-- HIGH-005: Database Schema for Role-Based Access Control
-- Implements immutable user-to-role mappings with audit trail
--
-- Security Features:
-- - Immutable audit trail (user_roles never updated/deleted)
-- - MFA support with TOTP
-- - Admin approval workflow for role grants
-- - Complete authorization audit logging

-- Enable foreign key constraints
PRAGMA foreign_keys = ON;

-- ============================================================================
-- 1. users - User Identity Registry
-- ============================================================================

CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,

  -- Discord Identity
  discord_user_id TEXT NOT NULL UNIQUE,
  discord_username TEXT NOT NULL,
  discord_discriminator TEXT,

  -- Linear Identity (optional)
  linear_user_id TEXT UNIQUE,
  linear_email TEXT,

  -- Department/Team Assignment
  department TEXT,
  team TEXT,

  -- Status
  status TEXT NOT NULL DEFAULT 'active',

  -- Metadata
  first_seen_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,

  CHECK (status IN ('active', 'suspended', 'deactivated'))
);

CREATE INDEX IF NOT EXISTS idx_users_discord_id ON users(discord_user_id);
CREATE INDEX IF NOT EXISTS idx_users_status ON users(status);
CREATE INDEX IF NOT EXISTS idx_users_department ON users(department);

-- ============================================================================
-- 2. user_roles - Role Assignments (Immutable Audit Trail)
-- ============================================================================

CREATE TABLE IF NOT EXISTS user_roles (
  id INTEGER PRIMARY KEY AUTOINCREMENT,

  -- Foreign Key to users table
  user_id INTEGER NOT NULL,

  -- Role Assignment
  role TEXT NOT NULL,
  action TEXT NOT NULL,

  -- Authorization Context
  granted_by_user_id INTEGER,
  granted_by_discord_id TEXT,
  approval_id INTEGER,

  -- Reason and Context
  reason TEXT,
  metadata TEXT,

  -- Timestamps
  effective_at TEXT NOT NULL,
  expires_at TEXT,
  created_at TEXT NOT NULL,

  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (granted_by_user_id) REFERENCES users(id),
  CHECK (role IN ('admin', 'developer', 'researcher', 'guest')),
  CHECK (action IN ('granted', 'revoked'))
);

CREATE INDEX IF NOT EXISTS idx_user_roles_user_id ON user_roles(user_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_role ON user_roles(role);
CREATE INDEX IF NOT EXISTS idx_user_roles_action ON user_roles(action);
CREATE INDEX IF NOT EXISTS idx_user_roles_effective_at ON user_roles(effective_at);

-- ============================================================================
-- 3. role_approvals - Admin Approval Workflow
-- ============================================================================

CREATE TABLE IF NOT EXISTS role_approvals (
  id INTEGER PRIMARY KEY AUTOINCREMENT,

  -- Request Details
  requested_user_id INTEGER NOT NULL,
  requested_role TEXT NOT NULL,
  requested_department TEXT,

  -- Requester Info
  requester_discord_id TEXT NOT NULL,
  requester_username TEXT NOT NULL,

  -- Approval Status
  status TEXT NOT NULL DEFAULT 'pending',

  -- Approver Info
  approver_user_id INTEGER,
  approver_discord_id TEXT,
  approval_reason TEXT,

  -- Timestamps
  requested_at TEXT NOT NULL,
  reviewed_at TEXT,
  expires_at TEXT NOT NULL,

  FOREIGN KEY (requested_user_id) REFERENCES users(id),
  FOREIGN KEY (approver_user_id) REFERENCES users(id),
  CHECK (status IN ('pending', 'approved', 'rejected', 'expired')),
  CHECK (requested_role IN ('admin', 'developer', 'researcher'))
);

CREATE INDEX IF NOT EXISTS idx_role_approvals_status ON role_approvals(status);
CREATE INDEX IF NOT EXISTS idx_role_approvals_requested_user ON role_approvals(requested_user_id);
CREATE INDEX IF NOT EXISTS idx_role_approvals_expires_at ON role_approvals(expires_at);

-- ============================================================================
-- 4. mfa_enrollments - Multi-Factor Authentication
-- ============================================================================

CREATE TABLE IF NOT EXISTS mfa_enrollments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,

  -- Foreign Key to users table
  user_id INTEGER NOT NULL UNIQUE,

  -- MFA Type
  mfa_type TEXT NOT NULL DEFAULT 'totp',

  -- TOTP Secret (encrypted at rest)
  totp_secret TEXT,
  backup_codes TEXT,

  -- Status
  status TEXT NOT NULL DEFAULT 'pending',

  -- Verification
  verified_at TEXT,
  last_used_at TEXT,

  -- Metadata
  enrolled_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,

  FOREIGN KEY (user_id) REFERENCES users(id),
  CHECK (mfa_type IN ('totp', 'sms', 'email')),
  CHECK (status IN ('pending', 'active', 'disabled'))
);

CREATE INDEX IF NOT EXISTS idx_mfa_enrollments_user_id ON mfa_enrollments(user_id);
CREATE INDEX IF NOT EXISTS idx_mfa_enrollments_status ON mfa_enrollments(status);

-- ============================================================================
-- 5. mfa_challenges - MFA Verification Log
-- ============================================================================

CREATE TABLE IF NOT EXISTS mfa_challenges (
  id INTEGER PRIMARY KEY AUTOINCREMENT,

  -- Foreign Key to users table
  user_id INTEGER NOT NULL,

  -- Challenge Details
  challenge_type TEXT NOT NULL,
  operation TEXT NOT NULL,
  operation_context TEXT,

  -- Verification Result
  success BOOLEAN NOT NULL,
  failure_reason TEXT,

  -- Security Context
  ip_address TEXT,
  user_agent TEXT,

  -- Timestamps
  challenged_at TEXT NOT NULL,

  FOREIGN KEY (user_id) REFERENCES users(id),
  CHECK (challenge_type IN ('totp', 'backup_code', 'sms', 'email'))
);

CREATE INDEX IF NOT EXISTS idx_mfa_challenges_user_id ON mfa_challenges(user_id);
CREATE INDEX IF NOT EXISTS idx_mfa_challenges_success ON mfa_challenges(success);
CREATE INDEX IF NOT EXISTS idx_mfa_challenges_challenged_at ON mfa_challenges(challenged_at);

-- ============================================================================
-- 6. auth_audit_log - Complete Authorization Audit Trail
-- ============================================================================

CREATE TABLE IF NOT EXISTS auth_audit_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,

  -- User Context
  user_id INTEGER,
  discord_user_id TEXT,
  discord_username TEXT,

  -- Authorization Check
  operation TEXT NOT NULL,
  resource TEXT,
  required_role TEXT,
  required_permission TEXT,

  -- Outcome
  granted BOOLEAN NOT NULL,
  denial_reason TEXT,

  -- Security Context
  ip_address TEXT,
  user_agent TEXT,
  channel_id TEXT,
  guild_id TEXT,

  -- MFA Context
  mfa_required BOOLEAN NOT NULL DEFAULT 0,
  mfa_verified BOOLEAN,

  -- Timestamps
  timestamp TEXT NOT NULL,

  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_auth_audit_log_user_id ON auth_audit_log(user_id);
CREATE INDEX IF NOT EXISTS idx_auth_audit_log_granted ON auth_audit_log(granted);
CREATE INDEX IF NOT EXISTS idx_auth_audit_log_timestamp ON auth_audit_log(timestamp);
CREATE INDEX IF NOT EXISTS idx_auth_audit_log_operation ON auth_audit_log(operation);
