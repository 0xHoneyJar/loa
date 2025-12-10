/**
 * Secret Scanner Tests
 *
 * Validates secret detection and redaction logic.
 * Tests for CRITICAL-005 remediation.
 */

import { SecretScanner } from '../../src/services/secret-scanner';

describe('SecretScanner', () => {
  let scanner: SecretScanner;

  beforeEach(() => {
    scanner = new SecretScanner();
  });

  describe('Stripe Keys', () => {
    test('should detect Stripe live secret keys', () => {
      // Using clearly fake key for testing (pattern matches but not a real key)
      const content = 'Payment API key: sk_live_TESTKEY123456789012345';
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);
      expect(result.totalSecretsFound).toBeGreaterThan(0);

      const stripeSecret = result.secrets.find(s => s.type === 'STRIPE_SECRET_KEY_LIVE');
      expect(stripeSecret).toBeDefined();
      expect(stripeSecret?.severity).toBe('CRITICAL');
      expect(result.redactedContent).toContain('[REDACTED: STRIPE_SECRET_KEY_LIVE]');
    });

    test('should detect Stripe test secret keys', () => {
      const content = 'Test key: sk_test_TESTKEY123456789012345';
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);

      const stripeTest = result.secrets.find(s => s.type === 'STRIPE_SECRET_KEY_TEST');
      expect(stripeTest).toBeDefined();
      expect(stripeTest?.severity).toBe('HIGH');
    });

    test('should detect Stripe publishable keys', () => {
      const content = 'Frontend key: pk_live_TESTKEY123456789012345';
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);

      const stripePub = result.secrets.find(s => s.type === 'STRIPE_PUBLISHABLE_KEY_LIVE');
      expect(stripePub).toBeDefined();
    });
  });

  describe('GitHub Tokens', () => {
    test('should detect GitHub Personal Access Tokens', () => {
      const content = 'Clone repo with: ghp_abcdefghijklmnopqrstuvwxyz123456';
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);

      const githubPAT = result.secrets.find(s => s.type === 'GITHUB_PAT');
      expect(githubPAT).toBeDefined();
      expect(githubPAT?.severity).toBe('CRITICAL');
      expect(result.redactedContent).toContain('[REDACTED: GITHUB_PAT]');
    });

    test('should detect GitHub OAuth tokens', () => {
      const content = 'OAuth token: gho_abcdefghijklmnopqrstuvwxyz123456';
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);

      const githubOAuth = result.secrets.find(s => s.type === 'GITHUB_OAUTH_TOKEN');
      expect(githubOAuth).toBeDefined();
      expect(githubOAuth?.severity).toBe('CRITICAL');
    });

    test('should detect GitHub fine-grained PATs', () => {
      const content = 'New token: github_pat_' + 'A'.repeat(82);
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);

      const fineGrained = result.secrets.find(s => s.type === 'GITHUB_FINE_GRAINED_PAT');
      expect(fineGrained).toBeDefined();
    });
  });

  describe('AWS Credentials', () => {
    test('should detect AWS access key IDs', () => {
      const content = 'AWS key: AKIAIOSFODNN7EXAMPLE';
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);

      const awsKey = result.secrets.find(s => s.type === 'AWS_ACCESS_KEY_ID');
      expect(awsKey).toBeDefined();
      expect(awsKey?.severity).toBe('CRITICAL');
    });

    test('should detect AWS secret access keys', () => {
      const content = 'aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY';
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);

      const awsSecret = result.secrets.find(s => s.type === 'AWS_SECRET_ACCESS_KEY');
      expect(awsSecret).toBeDefined();
      expect(awsSecret?.severity).toBe('CRITICAL');
    });
  });

  describe('Google Cloud Credentials', () => {
    test('should detect Google API keys', () => {
      const content = 'Maps API: AIzaSyDaGmWKa4JsXZ-HjGw7ISLn_3namBGewQe';
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);

      const googleAPI = result.secrets.find(s => s.type === 'GOOGLE_API_KEY');
      expect(googleAPI).toBeDefined();
      expect(googleAPI?.severity).toBe('CRITICAL');
    });

    test('should detect Google OAuth tokens', () => {
      const content = 'Token: ya29.a0AfH6SMBx...long_token_here';
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);

      const googleOAuth = result.secrets.find(s => s.type === 'GOOGLE_OAUTH_TOKEN');
      expect(googleOAuth).toBeDefined();
    });
  });

  describe('Anthropic API Keys', () => {
    test('should detect Anthropic API keys', () => {
      const content = 'Claude API: sk-ant-api03-' + 'A'.repeat(95);
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);

      const anthropicKey = result.secrets.find(s => s.type === 'ANTHROPIC_API_KEY');
      expect(anthropicKey).toBeDefined();
      expect(anthropicKey?.severity).toBe('CRITICAL');
    });
  });

  describe('Discord Tokens', () => {
    test('should detect Discord bot tokens', () => {
      // Using fake token format for testing (24.6.27 structure)
      const token = 'AAAABBBBCCCCDDDDEEEEFFFFG.AbCdEf.GHIJKLMNOPQRSTUVWXYZ123456';
      const content = `Bot token: ${token}`;
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);

      const discordBot = result.secrets.find(s => s.type === 'DISCORD_BOT_TOKEN');
      expect(discordBot).toBeDefined();
      expect(discordBot?.severity).toBe('CRITICAL');
    });
  });

  describe('Private Keys', () => {
    test('should detect RSA private keys', () => {
      const content = `
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA1234567890abcdef...
-----END RSA PRIVATE KEY-----
      `;
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);

      const privateKey = result.secrets.find(s => s.type === 'PRIVATE_KEY');
      expect(privateKey).toBeDefined();
      expect(privateKey?.severity).toBe('CRITICAL');
    });

    test('should detect EC private keys', () => {
      const content = '-----BEGIN EC PRIVATE KEY-----\nMHcCAQEE...';
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);
      expect(result.secrets.some(s => s.type === 'PRIVATE_KEY')).toBe(true);
    });

    test('should detect OpenSSH private keys', () => {
      const content = '-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjE...';
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);
      expect(result.secrets.some(s => s.type === 'PRIVATE_KEY')).toBe(true);
    });
  });

  describe('Database Connection Strings', () => {
    test('should detect PostgreSQL connection strings with credentials', () => {
      const content = 'DB: postgres://admin:mypassword123@localhost:5432/mydb';
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);

      const postgres = result.secrets.find(s => s.type === 'POSTGRES_CONNECTION_STRING');
      expect(postgres).toBeDefined();
      expect(postgres?.severity).toBe('CRITICAL');
    });

    test('should detect MySQL connection strings with credentials', () => {
      const content = 'mysql://root:secret123@db.example.com:3306/app_db';
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);

      const mysql = result.secrets.find(s => s.type === 'MYSQL_CONNECTION_STRING');
      expect(mysql).toBeDefined();
    });

    test('should detect MongoDB connection strings with credentials', () => {
      const content = 'mongodb://user:pass123@cluster.mongodb.net/test';
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);

      const mongo = result.secrets.find(s => s.type === 'MONGODB_CONNECTION_STRING');
      expect(mongo).toBeDefined();
    });

    test('should detect MongoDB+srv connection strings', () => {
      const content = 'mongodb+srv://admin:secretpass@cluster0.mongodb.net/mydb';
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);
      expect(result.secrets.some(s => s.type === 'MONGODB_CONNECTION_STRING')).toBe(true);
    });
  });

  describe('JWT Tokens', () => {
    test('should detect JWT tokens', () => {
      const jwt = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U';
      const content = `Authorization: Bearer ${jwt}`;
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);

      const jwtToken = result.secrets.find(s => s.type === 'JWT_TOKEN');
      expect(jwtToken).toBeDefined();
      expect(jwtToken?.severity).toBe('HIGH');
    });
  });

  describe('Generic Patterns', () => {
    test('should detect password assignments', () => {
      const content = 'password: mySecretPassword123!';
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);

      const password = result.secrets.find(s => s.type === 'PASSWORD_IN_TEXT');
      expect(password).toBeDefined();
      expect(password?.severity).toBe('HIGH');
    });

    test('should detect api_key assignments', () => {
      const content = 'api_key = "abc123def456ghi789jkl012mno345"';
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);

      const apiKey = result.secrets.find(s => s.type === 'API_KEY_GENERIC');
      expect(apiKey).toBeDefined();
    });

    test('should detect secret assignments', () => {
      const content = 'secret: "very-secret-string-12345678"';
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);

      const secret = result.secrets.find(s => s.type === 'SECRET_GENERIC');
      expect(secret).toBeDefined();
    });

    test('should detect token assignments', () => {
      const content = 'token = "abcdef1234567890abcdef1234567890"';
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);

      const token = result.secrets.find(s => s.type === 'TOKEN_GENERIC');
      expect(token).toBeDefined();
    });
  });

  describe('Third-Party Services', () => {
    test('should detect Slack tokens', () => {
      // Using fake Slack token format for testing (xoxb pattern)
      const content = 'xoxb-FAKE000000-FAKE000000000-EXAMPLEKEYEXAMPLEKEYEXAM';
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);

      const slack = result.secrets.find(s => s.type === 'SLACK_TOKEN');
      expect(slack).toBeDefined();
      expect(slack?.severity).toBe('CRITICAL');
    });

    test('should detect Twilio account SIDs', () => {
      // Using fake Twilio SID format for testing
      const content = 'Account: ACTESTKEY0123456789TESTKEY012345';
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);

      const twilio = result.secrets.find(s => s.type === 'TWILIO_ACCOUNT_SID');
      expect(twilio).toBeDefined();
    });

    test('should detect SendGrid API keys', () => {
      const content = 'SG.abcdefghijklmnopqrstuv.ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnop';
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);

      const sendgrid = result.secrets.find(s => s.type === 'SENDGRID_API_KEY');
      expect(sendgrid).toBeDefined();
    });

    test('should detect npm tokens', () => {
      const content = 'npm_abc123def456ghi789jkl012mno345pqr';
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);

      const npm = result.secrets.find(s => s.type === 'NPM_TOKEN');
      expect(npm).toBeDefined();
    });

    test('should detect GitLab Personal Access Tokens', () => {
      const content = 'glpat-abcdefghijklmnopqrst';
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);

      const gitlab = result.secrets.find(s => s.type === 'GITLAB_PAT');
      expect(gitlab).toBeDefined();
      expect(gitlab?.severity).toBe('CRITICAL');
    });
  });

  describe('Secret Redaction', () => {
    test('should redact all detected secrets', () => {
      const content = `
Our API credentials:
- Stripe: sk_live_TESTKEY123456789012345
- GitHub: ghp_abcdefghijklmnopqrstuvwxyz123456
- AWS: AKIAIOSFODNN7EXAMPLE
      `;

      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);
      expect(result.totalSecretsFound).toBeGreaterThanOrEqual(3);

      // Check redaction
      expect(result.redactedContent).not.toContain('sk_live_TESTKEY123456789012345');
      expect(result.redactedContent).not.toContain('ghp_abcdefghijklmnopqrstuvwxyz123456');
      expect(result.redactedContent).not.toContain('AKIAIOSFODNN7EXAMPLE');

      expect(result.redactedContent).toContain('[REDACTED: STRIPE_SECRET_KEY_LIVE]');
      expect(result.redactedContent).toContain('[REDACTED: GITHUB_PAT]');
      expect(result.redactedContent).toContain('[REDACTED: AWS_ACCESS_KEY_ID]');
    });

    test('should preserve non-secret content when redacting', () => {
      const content = 'API key: sk_live_TESTKEY1234567890123, Database: postgres://user:pass@host';
      const result = scanner.scanForSecrets(content);

      expect(result.redactedContent).toContain('API key:');
      expect(result.redactedContent).toContain('Database:');
      expect(result.redactedContent).toContain('[REDACTED');
    });
  });

  describe('Context Extraction', () => {
    test('should provide context around detected secrets', () => {
      const content = 'Configure the payment API with key: sk_live_TESTKEY123456789012345 for production.';
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);

      const secret = result.secrets[0];
      expect(secret.context).toBeDefined();
      expect(secret.context).toContain('Configure the payment API');
      expect(secret.context).toContain('for production');
    });

    test('should include location of detected secret', () => {
      const content = 'Some text before. API key: sk_live_TESTKEY1234567890123 and text after.';
      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);

      const secret = result.secrets[0];
      expect(secret.location).toBeGreaterThan(0);
      expect(content.substring(secret.location, secret.location + secret.value.length)).toBe(secret.value);
    });
  });

  describe('False Positive Filtering', () => {
    test('should skip git commit hashes (long alphanumeric)', () => {
      const content = 'Commit: abcdef1234567890abcdef1234567890abcdef12';
      const result = scanner.scanForSecrets(content);

      // Should not detect as LONG_ALPHANUMERIC_STRING (false positive)
      const longString = result.secrets.find(s => s.type === 'LONG_ALPHANUMERIC_STRING');
      expect(longString).toBeUndefined();
    });

    test('should skip example/placeholder contexts', () => {
      const content = 'Example password: examplePassword123 (not real)';
      const result = scanner.scanForSecrets(content, { skipFalsePositives: true });

      // Should skip due to "example" in context
      const password = result.secrets.find(s => s.type === 'PASSWORD_IN_TEXT');
      expect(password).toBeUndefined();
    });
  });

  describe('Multi-Secret Detection', () => {
    test('should detect multiple secrets in same content', () => {
      const content = `
Engineer writes in PRD:
"API Endpoint: https://api.stripe.com/v1/charges
Authentication: sk_live_TESTKEY123456789012345
GitHub Token: ghp_abcdefghijklmnopqrstuvwxyz123456
Database: postgres://admin:password123@localhost:5432/db"
      `;

      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);
      expect(result.totalSecretsFound).toBeGreaterThanOrEqual(3);

      // Verify different types detected
      expect(result.secrets.some(s => s.type === 'STRIPE_SECRET_KEY_LIVE')).toBe(true);
      expect(result.secrets.some(s => s.type === 'GITHUB_PAT')).toBe(true);
      expect(result.secrets.some(s => s.type === 'POSTGRES_CONNECTION_STRING')).toBe(true);
    });

    test('should count critical vs non-critical secrets', () => {
      const content = `
Critical: sk_live_TESTKEY1234567890123
Non-Critical: sk_test_TESTKEY1234567890123
      `;

      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(true);
      expect(result.criticalSecretsFound).toBeGreaterThan(0);
      expect(result.totalSecretsFound).toBeGreaterThan(result.criticalSecretsFound);
    });
  });

  describe('No Secrets', () => {
    test('should return no secrets for clean content', () => {
      const content = `
This is a normal document with no secrets.
We discuss API design, database schemas, and architecture.
No credentials are included in this document.
      `;

      const result = scanner.scanForSecrets(content);

      expect(result.hasSecrets).toBe(false);
      expect(result.totalSecretsFound).toBe(0);
      expect(result.criticalSecretsFound).toBe(0);
      expect(result.secrets.length).toBe(0);
      expect(result.redactedContent).toBe(content);
    });
  });

  describe('Statistics', () => {
    test('should provide pattern statistics', () => {
      const stats = scanner.getStatistics();

      expect(stats.totalPatterns).toBeGreaterThanOrEqual(50);
      expect(stats.criticalPatterns).toBeGreaterThan(0);
      expect(stats.highPatterns).toBeGreaterThan(0);
      expect(stats.mediumPatterns).toBeGreaterThan(0);

      // Total should equal sum of severity levels
      expect(stats.totalPatterns).toBe(
        stats.criticalPatterns + stats.highPatterns + stats.mediumPatterns
      );
    });
  });

  describe('Attack Scenario Prevention', () => {
    test('should prevent CRITICAL-005 attack: Stripe key in PRD', () => {
      // Scenario from remediation plan (using test key)
      const content = `
Engineer writes in PRD:
"API Endpoint: https://api.stripe.com/v1/charges
Authentication: sk_live_TESTKEY123456789012345 (production key)"
      `;

      const result = scanner.scanForSecrets(content);

      // Must detect and redact
      expect(result.hasSecrets).toBe(true);
      expect(result.criticalSecretsFound).toBeGreaterThan(0);

      const stripeKey = result.secrets.find(s => s.type === 'STRIPE_SECRET_KEY_LIVE');
      expect(stripeKey).toBeDefined();
      expect(stripeKey?.severity).toBe('CRITICAL');

      // Redacted content should not contain original key
      expect(result.redactedContent).not.toContain('sk_live_TESTKEY123456789012345');
      expect(result.redactedContent).toContain('[REDACTED: STRIPE_SECRET_KEY_LIVE]');
    });
  });
});
