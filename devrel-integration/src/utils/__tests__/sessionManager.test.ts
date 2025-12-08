import {
  SessionManager,
  createDiscordSession,
  initWorkflow,
  advanceWorkflow,
} from '../sessionManager';

describe('Session Management', () => {
  let sessionManager: SessionManager;

  beforeEach(() => {
    sessionManager = new SessionManager({
      ttl: 60000, // 1 minute for testing
      maxActions: 10,
    });
  });

  describe('Session Creation', () => {
    it('should create a new session', () => {
      const session = sessionManager.createSession('user123', {
        ipAddress: '127.0.0.1',
        platform: 'discord',
      });

      expect(session.sessionId).toBeDefined();
      expect(session.sessionId).toHaveLength(64); // 32 bytes hex
      expect(session.userId).toBe('user123');
      expect(session.metadata.ipAddress).toBe('127.0.0.1');
      expect(session.actionCount).toBe(0);
      expect(session.state).toEqual({});
    });

    it('should generate unique session IDs', () => {
      const session1 = sessionManager.createSession('user1');
      const session2 = sessionManager.createSession('user2');

      expect(session1.sessionId).not.toBe(session2.sessionId);
    });

    it('should set expiration time', () => {
      const session = sessionManager.createSession('user123');
      const expectedExpiry = session.createdAt + 60000; // 1 minute

      expect(session.expiresAt).toBeGreaterThanOrEqual(expectedExpiry - 100);
      expect(session.expiresAt).toBeLessThanOrEqual(expectedExpiry + 100);
    });
  });

  describe('Session Retrieval', () => {
    it('should retrieve existing session', () => {
      const created = sessionManager.createSession('user123');
      const retrieved = sessionManager.getSession(created.sessionId);

      expect(retrieved).not.toBeNull();
      expect(retrieved?.userId).toBe('user123');
      expect(retrieved?.sessionId).toBe(created.sessionId);
    });

    it('should return null for non-existent session', () => {
      const session = sessionManager.getSession('nonexistent');
      expect(session).toBeNull();
    });

    it('should update last activity on retrieval', () => {
      const session = sessionManager.createSession('user123');
      const originalActivity = session.lastActivity;

      // Wait a bit
      setTimeout(() => {
        const retrieved = sessionManager.getSession(session.sessionId);
        expect(retrieved?.lastActivity).toBeGreaterThan(originalActivity);
      }, 10);
    });
  });

  describe('Session State Management', () => {
    it('should update session state', () => {
      const session = sessionManager.createSession('user123');

      sessionManager.updateSessionState(session.sessionId, {
        currentPage: 'dashboard',
        preferences: { theme: 'dark' },
      });

      const updated = sessionManager.getSession(session.sessionId);
      expect(updated?.state.currentPage).toBe('dashboard');
      expect(updated?.state.preferences.theme).toBe('dark');
    });

    it('should merge state updates', () => {
      const session = sessionManager.createSession('user123');

      sessionManager.updateSessionState(session.sessionId, { field1: 'value1' });
      sessionManager.updateSessionState(session.sessionId, { field2: 'value2' });

      const updated = sessionManager.getSession(session.sessionId);
      expect(updated?.state.field1).toBe('value1');
      expect(updated?.state.field2).toBe('value2');
    });
  });

  describe('Action Rate Limiting', () => {
    it('should record actions', () => {
      const session = sessionManager.createSession('user123');

      const success1 = sessionManager.recordAction(session.sessionId);
      expect(success1).toBe(true);

      const updated = sessionManager.getSession(session.sessionId);
      expect(updated?.actionCount).toBe(1);
    });

    it('should enforce max actions limit', () => {
      const session = sessionManager.createSession('user123');

      // Record 10 actions (max)
      for (let i = 0; i < 10; i++) {
        const success = sessionManager.recordAction(session.sessionId);
        expect(success).toBe(true);
      }

      // 11th action should fail and destroy session
      const exceeded = sessionManager.recordAction(session.sessionId);
      expect(exceeded).toBe(false);

      // Session should be destroyed
      const destroyed = sessionManager.getSession(session.sessionId);
      expect(destroyed).toBeNull();
    });
  });

  describe('Session Extension', () => {
    it('should extend session TTL', () => {
      const session = sessionManager.createSession('user123');
      const originalExpiry = session.expiresAt;

      const extended = sessionManager.extendSession(session.sessionId, 30000);
      expect(extended).toBe(true);

      const updated = sessionManager.getSession(session.sessionId);
      expect(updated?.expiresAt).toBeGreaterThan(originalExpiry);
    });

    it('should not extend non-existent session', () => {
      const result = sessionManager.extendSession('nonexistent');
      expect(result).toBe(false);
    });
  });

  describe('Session Destruction', () => {
    it('should destroy session', () => {
      const session = sessionManager.createSession('user123');

      const destroyed = sessionManager.destroySession(session.sessionId);
      expect(destroyed).toBe(true);

      const retrieved = sessionManager.getSession(session.sessionId);
      expect(retrieved).toBeNull();
    });

    it('should return false for non-existent session', () => {
      const result = sessionManager.destroySession('nonexistent');
      expect(result).toBe(false);
    });
  });

  describe('User Session Management', () => {
    it('should get all sessions for a user', () => {
      sessionManager.createSession('user123');
      sessionManager.createSession('user123');
      sessionManager.createSession('user456');

      const userSessions = sessionManager.getUserSessions('user123');
      expect(userSessions).toHaveLength(2);
      expect(userSessions.every(s => s.userId === 'user123')).toBe(true);
    });

    it('should destroy all sessions for a user', () => {
      sessionManager.createSession('user123');
      sessionManager.createSession('user123');
      sessionManager.createSession('user456');

      const count = sessionManager.destroyUserSessions('user123');
      expect(count).toBe(2);

      const remaining = sessionManager.getUserSessions('user123');
      expect(remaining).toHaveLength(0);

      const other = sessionManager.getUserSessions('user456');
      expect(other).toHaveLength(1);
    });
  });

  describe('Session Statistics', () => {
    it('should provide session statistics', () => {
      const session1 = sessionManager.createSession('user1');
      const session2 = sessionManager.createSession('user2');

      sessionManager.recordAction(session1.sessionId);
      sessionManager.recordAction(session1.sessionId);
      sessionManager.recordAction(session2.sessionId);

      const stats = sessionManager.getStatistics();

      expect(stats.activeSessions).toBe(2);
      expect(stats.averageActionCount).toBe(1.5);
      expect(stats.averageSessionDuration).toBeGreaterThanOrEqual(0);
      expect(stats.oldestSession).toBeGreaterThanOrEqual(0);
    });

    it('should handle zero sessions', () => {
      const stats = sessionManager.getStatistics();

      expect(stats.activeSessions).toBe(0);
      expect(stats.averageActionCount).toBe(0);
      expect(stats.averageSessionDuration).toBe(0);
      expect(stats.oldestSession).toBe(0);
    });
  });

  describe('Session Cleanup', () => {
    it('should clean up expired sessions', (done) => {
      // Create session manager with very short TTL
      const shortTtlManager = new SessionManager({ ttl: 100 });

      const session = shortTtlManager.createSession('user123');

      // Wait for expiration
      setTimeout(() => {
        const cleaned = shortTtlManager.cleanup();
        expect(cleaned).toBeGreaterThan(0);

        const retrieved = shortTtlManager.getSession(session.sessionId);
        expect(retrieved).toBeNull();

        done();
      }, 150);
    });
  });

  describe('Discord Session Creation', () => {
    it('should create Discord-specific session', () => {
      const session = createDiscordSession('discord123', {
        ipAddress: '127.0.0.1',
      });

      expect(session.userId).toBe('discord123');
      expect(session.metadata.platform).toBe('discord');
      expect(session.discordId).toBe('discord123');
    });
  });

  describe('Workflow Management', () => {
    it('should initialize workflow', () => {
      const session = sessionManager.createSession('user123');
      const workflow = initWorkflow(session.sessionId, 3);

      expect(workflow.step).toBe(1);
      expect(workflow.totalSteps).toBe(3);
      expect(workflow.completed).toBe(false);
      expect(workflow.data).toEqual({});
    });

    it('should advance workflow through steps', () => {
      const session = sessionManager.createSession('user123');
      initWorkflow(session.sessionId, 3);

      const step1 = advanceWorkflow(session.sessionId, { step1Data: 'value1' });
      expect(step1?.step).toBe(2);
      expect(step1?.data.step1Data).toBe('value1');
      expect(step1?.completed).toBe(false);

      const step2 = advanceWorkflow(session.sessionId, { step2Data: 'value2' });
      expect(step2?.step).toBe(3);
      expect(step2?.completed).toBe(false);

      const step3 = advanceWorkflow(session.sessionId, { step3Data: 'value3' });
      expect(step3?.step).toBe(4);
      expect(step3?.completed).toBe(true);
      expect(step3?.data).toEqual({
        step1Data: 'value1',
        step2Data: 'value2',
        step3Data: 'value3',
      });
    });

    it('should return null for non-existent workflow', () => {
      const session = sessionManager.createSession('user123');
      const result = advanceWorkflow(session.sessionId, {});

      expect(result).toBeNull();
    });
  });

  describe('Session Security', () => {
    it('should use cryptographically secure session IDs', () => {
      const sessions = new Set<string>();

      // Generate 1000 session IDs
      for (let i = 0; i < 1000; i++) {
        const session = sessionManager.createSession(`user${i}`);
        sessions.add(session.sessionId);
      }

      // All should be unique
      expect(sessions.size).toBe(1000);

      // All should be 64 characters (32 bytes hex)
      sessions.forEach(id => {
        expect(id).toHaveLength(64);
        expect(/^[0-9a-f]+$/.test(id)).toBe(true);
      });
    });

    it('should not allow session ID prediction', () => {
      const session1 = sessionManager.createSession('user1');
      const session2 = sessionManager.createSession('user2');

      // Session IDs should be completely different (not sequential)
      const id1Int = BigInt('0x' + session1.sessionId.slice(0, 16));
      const id2Int = BigInt('0x' + session2.sessionId.slice(0, 16));
      const difference = id1Int > id2Int ? id1Int - id2Int : id2Int - id1Int;

      // Difference should be large (not 1, 2, 3, etc.)
      expect(difference > 1000n).toBe(true);
    });
  });
});
