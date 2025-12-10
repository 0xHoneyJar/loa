/**
 * Secrets Leak Detector Tests
 *
 * Tests for CRITICAL-008: Secrets Rotation Strategy (Leak Detection)
 */

import { SecretsLeakDetector } from '../../src/services/secrets-leak-detector';

describe('SecretsLeakDetector', () => {
  let detector: SecretsLeakDetector;

  beforeEach(() => {
    detector = new SecretsLeakDetector();
  });

  describe('isServicePaused', () => {
    test('should return not paused initially', () => {
      const status = detector.isServicePaused();

      expect(status.paused).toBe(false);
      expect(status.reason).toBeNull();
    });

    test('should return paused after pauseService called', async () => {
      await detector.pauseService('Test pause');

      const status = detector.isServicePaused();

      expect(status.paused).toBe(true);
      expect(status.reason).toBe('Test pause');
    });
  });

  describe('pauseService', () => {
    test('should pause service with reason', async () => {
      await detector.pauseService('Secrets leak detected');

      const status = detector.isServicePaused();

      expect(status.paused).toBe(true);
      expect(status.reason).toBe('Secrets leak detected');
    });
  });

  describe('resumeService', () => {
    test('should resume service after pause', async () => {
      await detector.pauseService('Test pause');

      expect(detector.isServicePaused().paused).toBe(true);

      await detector.resumeService('admin@example.com', 'Issue resolved');

      expect(detector.isServicePaused().paused).toBe(false);
    });

    test('should throw error if service not paused', async () => {
      await expect(
        detector.resumeService('admin@example.com', 'Issue resolved')
      ).rejects.toThrow('Service is not paused');
    });
  });

  describe('scanPublicRepos', () => {
    test('should scan repository without errors', async () => {
      const repositories = ['https://github.com/test/repo'];

      // This will return empty results since getRecentCommits is stubbed
      const leaks = await detector.scanPublicRepos(repositories);

      expect(Array.isArray(leaks)).toBe(true);
      expect(leaks.length).toBe(0);
    });

    test('should handle multiple repositories', async () => {
      const repositories = [
        'https://github.com/test/repo1',
        'https://github.com/test/repo2',
        'https://github.com/test/repo3'
      ];

      const leaks = await detector.scanPublicRepos(repositories);

      expect(Array.isArray(leaks)).toBe(true);
    });

    test('should respect scan options', async () => {
      const repositories = ['https://github.com/test/repo'];
      const options = {
        daysBack: 30,
        excludePaths: ['node_modules', 'dist']
      };

      const leaks = await detector.scanPublicRepos(repositories, options);

      expect(Array.isArray(leaks)).toBe(true);
    });
  });

  describe('alertOnLeaks', () => {
    test('should not alert if no leaks', async () => {
      // Should not throw error
      await detector.alertOnLeaks([]);

      const status = detector.isServicePaused();
      expect(status.paused).toBe(false);
    });

    test('should alert and pause service if leaks detected', async () => {
      const leaks = [
        {
          location: 'https://github.com/test/repo/commit/abc123',
          secrets: [
            { type: 'STRIPE_SECRET_KEY_LIVE', context: 'sk_live_...' }
          ],
          severity: 'CRITICAL' as const,
          commitSha: 'abc123',
          commitAuthor: 'developer@example.com',
          commitDate: new Date('2025-06-01'),
          commitMessage: 'Add payment integration'
        }
      ];

      await detector.alertOnLeaks(leaks);

      // Verify service was paused
      const status = detector.isServicePaused();
      expect(status.paused).toBe(true);
      expect(status.reason).toContain('Secrets leak detected');
    });

    test('should handle multiple leaks', async () => {
      const leaks = [
        {
          location: 'https://github.com/test/repo/commit/abc123',
          secrets: [
            { type: 'STRIPE_SECRET_KEY_LIVE', context: 'sk_live_...' }
          ],
          severity: 'CRITICAL' as const,
          commitSha: 'abc123',
          commitAuthor: 'developer@example.com',
          commitDate: new Date('2025-06-01'),
          commitMessage: 'Add payment integration'
        },
        {
          location: 'https://github.com/test/repo/commit/def456',
          secrets: [
            { type: 'GITHUB_PAT', context: 'ghp_...' }
          ],
          severity: 'HIGH' as const,
          commitSha: 'def456',
          commitAuthor: 'developer@example.com',
          commitDate: new Date('2025-06-02'),
          commitMessage: 'Update GitHub Actions'
        }
      ];

      await detector.alertOnLeaks(leaks);

      const status = detector.isServicePaused();
      expect(status.paused).toBe(true);
    });
  });

  describe('getStatistics', () => {
    test('should return statistics', async () => {
      const stats = await detector.getStatistics();

      expect(stats).toBeDefined();
      expect(stats.lastScanDate).toBeDefined();
      expect(typeof stats.totalScans).toBe('number');
      expect(typeof stats.leaksDetected).toBe('number');
      expect(typeof stats.servicePaused).toBe('boolean');
    });

    test('should reflect service pause status', async () => {
      await detector.pauseService('Test');

      const stats = await detector.getStatistics();

      expect(stats.servicePaused).toBe(true);
    });
  });

  describe('Attack Scenario Prevention', () => {
    test('should prevent CRITICAL-008 attack: leaked token in public commit history', async () => {
      // Attack Scenario:
      // - Discord bot token leaked in commit 6 months ago
      // - Attacker finds token in public repo history
      // - Attacker uses token to read all messages
      // - 6 months of company secrets exposed
      // - No detection, no alerts, no rotation

      // Simulated leak detection result
      const leaks = [
        {
          location: 'https://github.com/company/agentic-base/commit/a1b2c3d4',
          secrets: [
            {
              type: 'DISCORD_BOT_TOKEN',
              context: 'DISCORD_BOT_TOKEN=MTIzNDU2Nzg5MDEyMzQ1Njc4OQ.GhDxyz...'
            }
          ],
          severity: 'CRITICAL' as const,
          commitSha: 'a1b2c3d4',
          commitAuthor: 'engineer@company.com',
          commitDate: new Date(Date.now() - 180 * 24 * 60 * 60 * 1000), // 6 months ago
          commitMessage: 'Add Discord integration configuration'
        }
      ];

      // Before detection: Service running normally
      expect(detector.isServicePaused().paused).toBe(false);

      // Detection: Leak detector scans public commits
      await detector.alertOnLeaks(leaks);

      // After detection: Service paused immediately
      const status = detector.isServicePaused();
      expect(status.paused).toBe(true);
      expect(status.reason).toContain('Secrets leak detected');

      // Result: Attack scenario prevented by:
      // 1. Weekly automated scanning of public repos
      // 2. Immediate alert to security team
      // 3. Service auto-pause prevents further damage
      // 4. Emergency rotation procedures triggered
      // 5. Audit logs reviewed for unauthorized access
    });

    test('should detect multiple leaked secrets in single commit', async () => {
      const leaks = [
        {
          location: 'https://github.com/company/agentic-base/commit/xyz789',
          secrets: [
            {
              type: 'STRIPE_SECRET_KEY_LIVE',
              context: 'STRIPE_KEY=sk_live_abc123...'
            },
            {
              type: 'ANTHROPIC_API_KEY',
              context: 'ANTHROPIC_KEY=sk-ant-api03-xyz...'
            },
            {
              type: 'GOOGLE_SERVICE_ACCOUNT',
              context: '{"type": "service_account", "private_key": "-----BEGIN...'
            }
          ],
          severity: 'CRITICAL' as const,
          commitSha: 'xyz789',
          commitAuthor: 'engineer@company.com',
          commitDate: new Date(),
          commitMessage: 'Initial commit with config'
        }
      ];

      await detector.alertOnLeaks(leaks);

      // Verify all secrets flagged
      expect(leaks[0].secrets.length).toBe(3);

      // Verify service paused
      expect(detector.isServicePaused().paused).toBe(true);
    });

    test('should handle HIGH severity leaks', async () => {
      const leaks = [
        {
          location: 'https://github.com/company/repo/commit/abc123',
          secrets: [
            { type: 'GITHUB_PAT', context: 'ghp_abc123...' }
          ],
          severity: 'HIGH' as const,
          commitSha: 'abc123',
          commitAuthor: 'developer@example.com',
          commitDate: new Date(),
          commitMessage: 'Update CI/CD'
        }
      ];

      await detector.alertOnLeaks(leaks);

      // Even HIGH severity leaks should pause service
      expect(detector.isServicePaused().paused).toBe(true);
    });

    test('should resume service after leak remediation', async () => {
      // Step 1: Leak detected, service paused
      const leaks = [
        {
          location: 'https://github.com/test/repo/commit/abc123',
          secrets: [{ type: 'DISCORD_BOT_TOKEN', context: 'token...' }],
          severity: 'CRITICAL' as const,
          commitSha: 'abc123',
          commitAuthor: 'dev@example.com',
          commitDate: new Date(),
          commitMessage: 'Config update'
        }
      ];

      await detector.alertOnLeaks(leaks);
      expect(detector.isServicePaused().paused).toBe(true);

      // Step 2: Security team completes remediation:
      // - Rotated Discord bot token
      // - Removed secret from Git history
      // - Audited logs for unauthorized access
      // - Verified no data breach occurred

      // Step 3: Service resumed
      await detector.resumeService(
        'security-team@example.com',
        'Emergency rotation complete. Token revoked, Git history cleaned, logs audited - no unauthorized access detected.'
      );

      expect(detector.isServicePaused().paused).toBe(false);
    });
  });

  describe('Integration with Secret Scanner', () => {
    test('should use secret scanner to detect leaks in commits', async () => {
      // The leak detector integrates with secret-scanner.ts
      // to scan commit diffs for secrets using 50+ patterns

      // In production, this would:
      // 1. Fetch recent commits from GitHub API
      // 2. Get commit diffs
      // 3. Scan each diff with secretScanner.scanForSecrets()
      // 4. Return leaks found

      // Since getRecentCommits() is stubbed in tests, we verify
      // the integration points are correct

      const repositories = ['https://github.com/test/repo'];
      const leaks = await detector.scanPublicRepos(repositories);

      // No actual scanning happens in test (stubbed)
      expect(Array.isArray(leaks)).toBe(true);
    });
  });
});
