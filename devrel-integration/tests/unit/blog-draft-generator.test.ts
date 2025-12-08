/**
 * Blog Draft Generator Tests
 *
 * Tests for CRITICAL-007: Blog Publishing Security (Manual Draft Workflow)
 */

import { BlogDraftGenerator } from '../../src/services/blog-draft-generator';

describe('BlogDraftGenerator', () => {
  let generator: BlogDraftGenerator;

  beforeEach(() => {
    generator = new BlogDraftGenerator();
  });

  describe('generateDraft', () => {
    test('should generate draft with basic content', async () => {
      const draft = await generator.generateDraft(
        'Test Blog Post',
        'This is test content for a blog post.',
        ['doc1.md', 'doc2.md'],
        'user-123'
      );

      expect(draft.id).toBeDefined();
      expect(draft.title).toBe('Test Blog Post');
      expect(draft.content).toBe('This is test content for a blog post.');
      expect(draft.status).toBe('draft');
      expect(draft.createdBy).toBe('user-123');
      expect(draft.sourceDocuments).toEqual(['doc1.md', 'doc2.md']);
      expect(draft.metadata.wordCount).toBe(8);
      expect(draft.metadata.secretsDetected).toBe(false);
    });

    test('should detect and redact secrets in content', async () => {
      const content = `
Our payment system uses Stripe.
API Key: sk_live_TESTKEY123456789012345
      `;

      const draft = await generator.generateDraft(
        'Payment Integration',
        content,
        ['payment.md'],
        'user-123'
      );

      // Secrets should be detected
      expect(draft.metadata.secretsDetected).toBe(true);
      expect(draft.metadata.secretsRedacted).toBeGreaterThan(0);

      // Content should be redacted
      expect(draft.content).not.toContain('sk_live_TESTKEY123456789012345');
      expect(draft.content).toContain('[REDACTED: STRIPE_SECRET_KEY_LIVE]');
    });

    test('should flag sensitive content patterns', async () => {
      const content = `
Contact us at engineer@company.com
Revenue: $500,000
Internal API: https://internal.company.com/api
      `;

      const draft = await generator.generateDraft(
        'Company Update',
        content,
        ['update.md'],
        'user-123'
      );

      const flags = draft.metadata.sensitiveContentFlags;
      expect(flags).toContain('EMAIL_ADDRESS');
      expect(flags).toContain('DOLLAR_AMOUNT');
      expect(flags).toContain('INTERNAL_URL');
    });

    test('should generate redaction checklist', async () => {
      const draft = await generator.generateDraft(
        'Test Post',
        'Content',
        ['doc.md'],
        'user-123'
      );

      const checklist = draft.metadata.redactionChecklist;

      expect(checklist.length).toBe(17);
      expect(checklist.some(item => item.category === 'Secrets & Credentials')).toBe(true);
      expect(checklist.some(item => item.category === 'Business Sensitive')).toBe(true);
      expect(checklist.some(item => item.category === 'Security Sensitive')).toBe(true);
      expect(checklist.some(item => item.category === 'Legal & Compliance')).toBe(true);

      // All items should start unchecked
      expect(checklist.every(item => item.checked === false)).toBe(true);
    });

    test('should calculate word count correctly', async () => {
      const content = 'One two three four five six seven eight nine ten';

      const draft = await generator.generateDraft(
        'Test',
        content,
        ['doc.md'],
        'user-123'
      );

      expect(draft.metadata.wordCount).toBe(10);
    });
  });

  describe('markReadyForReview', () => {
    test('should change status from draft to ready_for_review', async () => {
      const draft = await generator.generateDraft('Test', 'Content', ['doc.md'], 'user-123');

      expect(draft.status).toBe('draft');

      const updated = await generator.markReadyForReview(draft.id);

      expect(updated.status).toBe('ready_for_review');
    });

    test('should throw error if draft not found', async () => {
      await expect(
        generator.markReadyForReview('nonexistent-id')
      ).rejects.toThrow('Draft not found');
    });

    test('should throw error if draft is not in draft status', async () => {
      const draft = await generator.generateDraft('Test', 'Content', ['doc.md'], 'user-123');
      await generator.markReadyForReview(draft.id);

      // Try to mark ready again
      await expect(
        generator.markReadyForReview(draft.id)
      ).rejects.toThrow('is not in draft status');
    });
  });

  describe('reviewDraft', () => {
    test('should approve draft', async () => {
      const draft = await generator.generateDraft('Test', 'Content', ['doc.md'], 'user-123');
      await generator.markReadyForReview(draft.id);

      const reviewed = await generator.reviewDraft(draft.id, 'reviewer-456', true);

      expect(reviewed.status).toBe('approved');
      expect(reviewed.reviewedBy).toBe('reviewer-456');
      expect(reviewed.reviewedAt).toBeDefined();
    });

    test('should reject draft with reason', async () => {
      const draft = await generator.generateDraft('Test', 'Content', ['doc.md'], 'user-123');
      await generator.markReadyForReview(draft.id);

      const reviewed = await generator.reviewDraft(
        draft.id,
        'reviewer-456',
        false,
        'Contains internal infrastructure details'
      );

      expect(reviewed.status).toBe('rejected');
      expect(reviewed.reviewedBy).toBe('reviewer-456');
      expect(reviewed.rejectionReason).toBe('Contains internal infrastructure details');
    });

    test('should throw error if draft not ready for review', async () => {
      const draft = await generator.generateDraft('Test', 'Content', ['doc.md'], 'user-123');

      await expect(
        generator.reviewDraft(draft.id, 'reviewer-456', true)
      ).rejects.toThrow('is not ready for review');
    });
  });

  describe('publishDraft', () => {
    test('should publish approved draft', async () => {
      const draft = await generator.generateDraft('Test', 'Clean content', ['doc.md'], 'user-123');
      await generator.markReadyForReview(draft.id);
      await generator.reviewDraft(draft.id, 'reviewer-456', true);

      const published = await generator.publishDraft(draft.id, 'publisher-789');

      expect(published.status).toBe('published');
      expect(published.publishedBy).toBe('publisher-789');
      expect(published.publishedAt).toBeDefined();
    });

    test('should block publishing if draft not approved', async () => {
      const draft = await generator.generateDraft('Test', 'Content', ['doc.md'], 'user-123');

      await expect(
        generator.publishDraft(draft.id, 'publisher-789')
      ).rejects.toThrow('status is draft, must be \'approved\'');
    });

    test('should block publishing if secrets detected', async () => {
      const content = 'API key: sk_live_TESTKEY123456789012345';
      const draft = await generator.generateDraft('Test', content, ['doc.md'], 'user-123');

      // Manually set status to approved to bypass workflow (for testing)
      const draftObj = generator.getDraft(draft.id)!;
      draftObj.status = 'approved';

      // Should block because secrets detected
      await expect(
        generator.publishDraft(draft.id, 'publisher-789')
      ).rejects.toThrow('secrets detected');
    });
  });

  describe('getDraft', () => {
    test('should retrieve draft by ID', async () => {
      const draft = await generator.generateDraft('Test', 'Content', ['doc.md'], 'user-123');

      const retrieved = generator.getDraft(draft.id);

      expect(retrieved).toBeDefined();
      expect(retrieved!.id).toBe(draft.id);
      expect(retrieved!.title).toBe('Test');
    });

    test('should return undefined for nonexistent draft', () => {
      const retrieved = generator.getDraft('nonexistent-id');

      expect(retrieved).toBeUndefined();
    });
  });

  describe('listDrafts', () => {
    test('should list all drafts', async () => {
      await generator.generateDraft('Draft 1', 'Content 1', ['doc1.md'], 'user-123');
      await generator.generateDraft('Draft 2', 'Content 2', ['doc2.md'], 'user-123');
      await generator.generateDraft('Draft 3', 'Content 3', ['doc3.md'], 'user-456');

      const drafts = generator.listDrafts();

      expect(drafts.length).toBe(3);
    });

    test('should filter drafts by status', async () => {
      const draft1 = await generator.generateDraft('Draft 1', 'Content 1', ['doc1.md'], 'user-123');
      const draft2 = await generator.generateDraft('Draft 2', 'Content 2', ['doc2.md'], 'user-123');

      await generator.markReadyForReview(draft1.id);

      const draftStatus = generator.listDrafts({ status: 'draft' });
      const reviewStatus = generator.listDrafts({ status: 'ready_for_review' });

      expect(draftStatus.length).toBe(1);
      expect(draftStatus[0].id).toBe(draft2.id);

      expect(reviewStatus.length).toBe(1);
      expect(reviewStatus[0].id).toBe(draft1.id);
    });

    test('should filter drafts by creator', async () => {
      await generator.generateDraft('Draft 1', 'Content 1', ['doc1.md'], 'user-123');
      await generator.generateDraft('Draft 2', 'Content 2', ['doc2.md'], 'user-123');
      await generator.generateDraft('Draft 3', 'Content 3', ['doc3.md'], 'user-456');

      const user123Drafts = generator.listDrafts({ createdBy: 'user-123' });
      const user456Drafts = generator.listDrafts({ createdBy: 'user-456' });

      expect(user123Drafts.length).toBe(2);
      expect(user456Drafts.length).toBe(1);
    });

    test('should sort drafts by created date (newest first)', async () => {
      const draft1 = await generator.generateDraft('Draft 1', 'Content 1', ['doc1.md'], 'user-123');
      // Small delay to ensure different timestamps
      await new Promise(resolve => setTimeout(resolve, 10));
      const draft2 = await generator.generateDraft('Draft 2', 'Content 2', ['doc2.md'], 'user-123');

      const drafts = generator.listDrafts();

      expect(drafts[0].id).toBe(draft2.id); // Newest first
      expect(drafts[1].id).toBe(draft1.id);
    });
  });

  describe('Attack Scenario Prevention', () => {
    test('should prevent CRITICAL-007 attack: auto-publishing with secrets', async () => {
      const content = `
# Payment System Architecture

Our Stripe integration uses the following credentials:
- Live API Key: sk_live_TESTKEY123456789012345
- Test API Key: sk_test_TESTKEY123456789012345
      `;

      // Generate draft
      const draft = await generator.generateDraft(
        'Payment Architecture',
        content,
        ['architecture.md'],
        'engineer-123'
      );

      // Verify secrets were detected and redacted
      expect(draft.metadata.secretsDetected).toBe(true);
      expect(draft.metadata.secretsRedacted).toBeGreaterThan(0);
      expect(draft.content).not.toContain('sk_live_TESTKEY123456789012345');
      expect(draft.content).not.toContain('sk_test_TESTKEY123456789012345');

      // Verify status is 'draft' (NOT published)
      expect(draft.status).toBe('draft');

      // Verify cannot publish without approval
      await expect(
        generator.publishDraft(draft.id, 'publisher-789')
      ).rejects.toThrow('status is draft, must be \'approved\'');

      // Even if we manually approve, publishing should block on final secret scan
      const draftObj = generator.getDraft(draft.id)!;
      draftObj.status = 'approved';

      await expect(
        generator.publishDraft(draft.id, 'publisher-789')
      ).rejects.toThrow('secrets detected');

      // Verify draft was NEVER published
      const finalDraft = generator.getDraft(draft.id)!;
      expect(finalDraft.status).not.toBe('published');
      expect(finalDraft.publishedAt).toBeUndefined();
    });

    test('should prevent publishing with sensitive content', async () => {
      const content = `
# Internal Infrastructure Update

Our database is hosted at https://internal.company.com/db
Contact: engineer@company.com
Cost: $500,000/year
      `;

      const draft = await generator.generateDraft(
        'Infrastructure Update',
        content,
        ['infrastructure.md'],
        'engineer-123'
      );

      // Verify sensitive content flagged
      expect(draft.metadata.sensitiveContentFlags.length).toBeGreaterThan(0);
      expect(draft.metadata.sensitiveContentFlags).toContain('INTERNAL_URL');
      expect(draft.metadata.sensitiveContentFlags).toContain('EMAIL_ADDRESS');
      expect(draft.metadata.sensitiveContentFlags).toContain('DOLLAR_AMOUNT');

      // Verify status is 'draft' (NOT published)
      expect(draft.status).toBe('draft');
    });
  });

  describe('getStatistics', () => {
    test('should return correct statistics', async () => {
      // Create drafts in different statuses
      const draft1 = await generator.generateDraft('Draft 1', 'Content with sk_live_TEST123', ['doc1.md'], 'user-123');
      const draft2 = await generator.generateDraft('Draft 2', 'Content', ['doc2.md'], 'user-123');
      const draft3 = await generator.generateDraft('Draft 3', 'https://internal.company.com', ['doc3.md'], 'user-456');

      await generator.markReadyForReview(draft2.id);
      await generator.reviewDraft(draft2.id, 'reviewer-789', true);

      const stats = generator.getStatistics();

      expect(stats.totalDrafts).toBe(3);
      expect(stats.draftsByStatus.draft).toBe(2);
      expect(stats.draftsByStatus.approved).toBe(1);
      expect(stats.draftsWithSecrets).toBeGreaterThan(0);
      expect(stats.draftsWithSensitiveContent).toBeGreaterThan(0);
    });
  });

  describe('Workflow Integration', () => {
    test('should complete full workflow: draft → review → approve → publish', async () => {
      // Step 1: Generate draft
      const draft = await generator.generateDraft(
        'New Feature: Authentication',
        'We implemented JWT-based authentication for our API.',
        ['auth.md'],
        'engineer-123'
      );

      expect(draft.status).toBe('draft');

      // Step 2: Mark ready for review
      await generator.markReadyForReview(draft.id);
      expect(generator.getDraft(draft.id)!.status).toBe('ready_for_review');

      // Step 3: Review and approve
      await generator.reviewDraft(draft.id, 'reviewer-456', true);
      expect(generator.getDraft(draft.id)!.status).toBe('approved');

      // Step 4: Publish
      await generator.publishDraft(draft.id, 'publisher-789');
      const published = generator.getDraft(draft.id)!;

      expect(published.status).toBe('published');
      expect(published.publishedBy).toBe('publisher-789');
      expect(published.publishedAt).toBeDefined();
    });

    test('should handle rejection and resubmission', async () => {
      // Generate draft
      const draft = await generator.generateDraft(
        'Feature Update',
        'Initial content with issues',
        ['update.md'],
        'engineer-123'
      );

      // Mark ready
      await generator.markReadyForReview(draft.id);

      // Reject with reason
      await generator.reviewDraft(
        draft.id,
        'reviewer-456',
        false,
        'Contains internal details that must be removed'
      );

      const rejected = generator.getDraft(draft.id)!;
      expect(rejected.status).toBe('rejected');
      expect(rejected.rejectionReason).toBe('Contains internal details that must be removed');

      // Cannot publish rejected draft
      await expect(
        generator.publishDraft(draft.id, 'publisher-789')
      ).rejects.toThrow('status is rejected, must be \'approved\'');
    });
  });
});
