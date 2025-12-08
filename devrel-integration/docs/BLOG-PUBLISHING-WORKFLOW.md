# Blog Publishing Workflow (CRITICAL-007)

This document describes the secure manual blog publishing workflow that prevents accidental exposure of internal technical details to the public internet.

## Table of Contents

1. [Overview](#overview)
2. [Security Model](#security-model)
3. [Workflow Steps](#workflow-steps)
4. [Draft Generation](#draft-generation)
5. [Manual Review Process](#manual-review-process)
6. [Manual Publishing](#manual-publishing)
7. [Redaction Checklist](#redaction-checklist)
8. [Code Examples](#code-examples)
9. [Best Practices](#best-practices)

## Overview

**Key Principle**: The system NEVER auto-publishes blog posts. All blog posts follow a manual workflow:

```
Content → Generate Draft → Manual Review → Manual Publish
```

This prevents the catastrophic scenario where internal technical details, secrets, or sensitive business information are irreversibly published to the public internet.

## Security Model

### Why Manual Publishing?

**Attack Scenario Prevented**:
- Engineer includes Stripe production key in architecture doc
- AI summarizes doc for blog post, includes key in summary
- Auto-publishing posts to blog → key exposed to public internet
- Attacker discovers key → charges $100k to company card
- **IRREVERSIBLE**: Cannot unpublish from blog, key compromised forever

### Security Controls

1. ✅ **No Auto-Publishing** - `auto_publish: false` hardcoded in config
2. ✅ **Draft-Only Generation** - System only creates drafts, never publishes
3. ✅ **Secret Scanning** - Automatic redaction before draft creation
4. ✅ **Manual Review Required** - Human reviews draft before approval
5. ✅ **Redaction Checklist** - 17-point checklist for sensitive content
6. ✅ **Final Secret Scan** - Additional scan before publishing
7. ✅ **Pre-Distribution Validation** - Validates content before publish
8. ✅ **Status Tracking** - Draft → Ready for Review → Approved → Published
9. ✅ **Audit Trail** - All operations logged with timestamps and user IDs
10. ✅ **Security Exception Blocking** - Publishing fails if secrets detected

## Workflow Steps

### Step 1: Generate Draft

The system generates a blog post draft from source documents:

```typescript
import { blogDraftGenerator } from '../services/blog-draft-generator';

const draft = await blogDraftGenerator.generateDraft(
  'New Feature: User Authentication',
  contentFromDocuments,
  ['docs/prd.md', 'docs/architecture.md'],
  'user-123'  // Discord user ID
);

console.log(`Draft created: ${draft.id}`);
console.log(`Status: ${draft.status}`);  // 'draft'
console.log(`Secrets detected: ${draft.metadata.secretsDetected}`);
console.log(`Secrets redacted: ${draft.metadata.secretsRedacted}`);
```

**What Happens**:
- ✅ Content scanned for 50+ secret patterns
- ✅ Detected secrets automatically redacted
- ✅ Sensitive content flagged (internal URLs, emails, amounts)
- ✅ Redaction checklist generated
- ✅ Draft saved with status 'draft'
- ❌ **NOT PUBLISHED** - only saved as draft

### Step 2: Mark Ready for Review

When draft is complete, mark it ready for review:

```typescript
const draft = await blogDraftGenerator.markReadyForReview(draftId);

console.log(`Status: ${draft.status}`);  // 'ready_for_review'
```

**What Happens**:
- ✅ Status changed from 'draft' → 'ready_for_review'
- ✅ Notifies reviewers (future: Discord/email notification)

### Step 3: Manual Review

A team member manually reviews the draft:

```typescript
// Reviewer examines draft content
const draft = blogDraftGenerator.getDraft(draftId);

console.log(`Title: ${draft.title}`);
console.log(`Content:\n${draft.content}`);
console.log(`Secrets detected: ${draft.metadata.secretsDetected}`);
console.log(`Sensitive flags: ${draft.metadata.sensitiveContentFlags.join(', ')}`);

// Review redaction checklist
for (const item of draft.metadata.redactionChecklist) {
  console.log(`[${item.checked ? '✓' : ' '}] ${item.category}: ${item.description}`);
}

// Approve or reject
const approved = await blogDraftGenerator.reviewDraft(
  draftId,
  'reviewer-user-id',
  true,  // approved = true
  undefined  // no rejection reason
);

console.log(`Status: ${approved.status}`);  // 'approved'
```

**Manual Review Checklist** (reviewer must verify):
1. Check all 17 redaction checklist items
2. Verify no secrets in content
3. Verify no internal URLs or infrastructure details
4. Verify no sensitive business information
5. Verify no unpatched vulnerabilities mentioned
6. Verify GDPR compliance (no PII)
7. Verify no confidential agreements referenced

### Step 4: Manual Publishing

After approval, authorized team member manually publishes:

```typescript
try {
  const published = await blogDraftGenerator.publishDraft(
    draftId,
    'publisher-user-id'
  );

  console.log(`✅ Published: ${published.title}`);
  console.log(`Published by: ${published.publishedBy}`);
  console.log(`Published at: ${published.publishedAt}`);

} catch (error) {
  // If secrets detected or validation fails, publishing is blocked
  console.error(`❌ Publishing blocked: ${error.message}`);
}
```

**What Happens**:
1. ✅ Verifies status is 'approved'
2. ✅ Final secret scan (blocks if secrets found)
3. ✅ Pre-distribution validation (blocks if sensitive patterns found)
4. ✅ Status changed to 'published'
5. ✅ Audit log created
6. ✅ Content can now be posted to blog platform

**Security Checks**:
- ❌ **BLOCKS** if status is not 'approved'
- ❌ **BLOCKS** if secrets detected in final scan
- ❌ **BLOCKS** if pre-distribution validation fails
- ❌ **BLOCKS** if any SecurityException thrown

## Draft Generation

### Automatic Security Features

When generating a draft, the system automatically:

1. **Secret Scanning**
   - Scans content for 50+ secret patterns
   - Detects: Stripe keys, GitHub tokens, AWS keys, database credentials, etc.
   - Severity classification: CRITICAL, HIGH, MEDIUM

2. **Automatic Redaction**
   - Replaces detected secrets with `[REDACTED: SECRET_TYPE]`
   - Example: `sk_live_abc123...` → `[REDACTED: STRIPE_SECRET_KEY_LIVE]`

3. **Sensitive Content Flagging**
   - Internal URLs: `https://internal.company.com`
   - Email addresses: `engineer@company.com`
   - Dollar amounts: `$500,000`
   - IP addresses: `192.168.1.1`
   - Username mentions: `@engineer`

4. **Metadata Tracking**
   - Word count
   - Secrets detected count
   - Secrets redacted count
   - List of sensitive content flags

### Example Draft Output

```typescript
{
  id: 'draft_1234567890_abc123',
  title: 'Building a Secure Payment System',
  content: 'We integrated Stripe using [REDACTED: STRIPE_SECRET_KEY_LIVE]...',
  status: 'draft',
  metadata: {
    wordCount: 850,
    secretsDetected: true,
    secretsRedacted: 2,
    sensitiveContentFlags: ['EMAIL_ADDRESS', 'INTERNAL_URL'],
    redactionChecklist: [
      { category: 'Secrets & Credentials', description: 'API keys redacted', checked: false },
      // ... 16 more items
    ]
  }
}
```

## Manual Review Process

### Reviewer Responsibilities

1. **Read entire draft carefully**
   - Check for technical accuracy
   - Check for tone/style consistency
   - Check for sensitive information

2. **Complete redaction checklist**
   - Review all 17 checklist items
   - Check boxes for completed items
   - Add notes where needed

3. **Verify automatic redactions**
   - Ensure `[REDACTED: TYPE]` markers are appropriate
   - Verify nothing sensitive slipped through

4. **Check sensitive content flags**
   - Review each flagged item
   - Determine if it's safe for public blog
   - Redact manually if needed

5. **Make approval decision**
   - Approve if all checks pass
   - Reject if issues found (with clear reason)

### Rejection Workflow

If draft is rejected:

```typescript
await blogDraftGenerator.reviewDraft(
  draftId,
  'reviewer-user-id',
  false,  // approved = false
  'Contains internal infrastructure details that must be removed before publishing'
);
```

Author receives rejection reason and can:
1. Edit the draft content
2. Regenerate draft with updated content
3. Resubmit for review

## Manual Publishing

### Authorization

Only explicitly authorized users can publish:

```yaml
# config/rbac-config.yaml
distribution:
  blog:
    authorized_publishers:
      - "123456789012345678"  # CTO
      - "987654321098765432"  # Head of Marketing
```

**Recommendation**: Keep this list to 1-2 people maximum.

### Publishing Checklist

Before clicking "publish", authorized publisher must:

1. ✅ Verify draft status is 'approved'
2. ✅ Verify reviewer completed redaction checklist
3. ✅ Re-read content one final time
4. ✅ Verify no breaking news that invalidates content
5. ✅ Verify blog platform is accessible
6. ✅ Have rollback plan ready (how to unpublish if needed)

### Publishing Example

```typescript
import { blogDraftGenerator } from '../services/blog-draft-generator';

async function publishBlogPost(draftId: string, publisherId: string) {
  try {
    // Attempt to publish
    const published = await blogDraftGenerator.publishDraft(draftId, publisherId);

    console.log('✅ PUBLISHED SUCCESSFULLY');
    console.log(`Title: ${published.title}`);
    console.log(`Published by: ${published.publishedBy}`);
    console.log(`Published at: ${published.publishedAt}`);

    // TODO: Actually post to blog platform (Mirror, Paragraph, etc.)
    // await blogPlatform.post(published.content);

    return published;

  } catch (error) {
    console.error('❌ PUBLISHING BLOCKED');
    console.error(`Reason: ${error.message}`);

    // Alert security team if secrets detected
    if (error.message.includes('secrets detected')) {
      await alertSecurityTeam({
        subject: '🚨 CRITICAL: Secrets detected in approved blog draft',
        draftId,
        error: error.message
      });
    }

    throw error;
  }
}
```

## Redaction Checklist

The system generates a 17-point checklist for manual review:

### Secrets & Credentials (4 items)
- [ ] API keys, tokens, passwords redacted
- [ ] Database connection strings removed
- [ ] Private keys and certificates removed
- [ ] Internal URLs and endpoints obscured

### Business Sensitive (5 items)
- [ ] Revenue numbers removed or rounded
- [ ] Customer names anonymized
- [ ] Pricing details redacted
- [ ] Competitive intelligence removed
- [ ] Unreleased product details removed

### Security Sensitive (4 items)
- [ ] Unpatched vulnerabilities removed
- [ ] Security architecture details obscured
- [ ] Internal infrastructure details removed
- [ ] Incident details anonymized

### Legal & Compliance (4 items)
- [ ] No PII exposed
- [ ] GDPR compliance verified
- [ ] No confidential agreements referenced
- [ ] No trademark/IP violations

## Code Examples

### Complete Workflow Example

```typescript
import { blogDraftGenerator } from '../services/blog-draft-generator';

// === STEP 1: Generate Draft ===
const content = `
# New Feature: Two-Factor Authentication

We've implemented 2FA using TOTP (Time-based One-Time Passwords).
Our implementation uses industry-standard libraries and follows OWASP guidelines.

Architecture:
- Frontend: React with QR code generation
- Backend: Node.js with speakeasy library
- Database: PostgreSQL for storing user secrets
`;

const draft = await blogDraftGenerator.generateDraft(
  'New Feature: Two-Factor Authentication',
  content,
  ['docs/2fa-prd.md', 'docs/2fa-architecture.md'],
  'user-123'
);

console.log(`Draft ID: ${draft.id}`);
console.log(`Status: ${draft.status}`);  // 'draft'

// === STEP 2: Mark Ready for Review ===
await blogDraftGenerator.markReadyForReview(draft.id);

console.log('✅ Draft ready for review');

// === STEP 3: Manual Review ===
const draftToReview = blogDraftGenerator.getDraft(draft.id);

// Reviewer examines content...
console.log('Reviewer checking redaction checklist...');

// Approve draft
await blogDraftGenerator.reviewDraft(
  draft.id,
  'reviewer-456',
  true  // approved
);

console.log('✅ Draft approved');

// === STEP 4: Manual Publishing ===
try {
  const published = await blogDraftGenerator.publishDraft(
    draft.id,
    'publisher-789'
  );

  console.log('✅ Published successfully');
  console.log(`Title: ${published.title}`);
  console.log(`Published at: ${published.publishedAt}`);

  // TODO: Post to actual blog platform
  // await blogPlatform.post({
  //   title: published.title,
  //   content: published.content,
  //   publishedAt: published.publishedAt
  // });

} catch (error) {
  console.error(`❌ Publishing failed: ${error.message}`);
}
```

### List Drafts by Status

```typescript
// Get all drafts pending review
const pendingReview = blogDraftGenerator.listDrafts({ status: 'ready_for_review' });

console.log(`Drafts pending review: ${pendingReview.length}`);
for (const draft of pendingReview) {
  console.log(`- ${draft.title} (created by ${draft.createdBy})`);
}

// Get all approved drafts
const approved = blogDraftGenerator.listDrafts({ status: 'approved' });

console.log(`Drafts ready to publish: ${approved.length}`);

// Get all published posts
const published = blogDraftGenerator.listDrafts({ status: 'published' });

console.log(`Published posts: ${published.length}`);
```

### Statistics

```typescript
const stats = blogDraftGenerator.getStatistics();

console.log(`Total drafts: ${stats.totalDrafts}`);
console.log(`By status:`);
console.log(`  - Draft: ${stats.draftsByStatus.draft}`);
console.log(`  - Ready for review: ${stats.draftsByStatus.ready_for_review}`);
console.log(`  - Approved: ${stats.draftsByStatus.approved}`);
console.log(`  - Published: ${stats.draftsByStatus.published}`);
console.log(`  - Rejected: ${stats.draftsByStatus.rejected}`);
console.log(`Drafts with secrets: ${stats.draftsWithSecrets}`);
console.log(`Drafts with sensitive content: ${stats.draftsWithSensitiveContent}`);
```

## Best Practices

### For Engineers Creating Content

1. **Never include secrets** - Use placeholders like `<STRIPE_KEY>` instead
2. **Avoid internal URLs** - Use generic examples like `https://api.example.com`
3. **Anonymize customer data** - Use "Acme Corp" instead of real names
4. **Round revenue numbers** - Use "$10M ARR" instead of exact figures
5. **Describe, don't expose** - Talk about architecture concepts, not implementation details

### For Reviewers

1. **Read entire draft** - Don't skip sections
2. **Check all checklist items** - Every single one
3. **Be paranoid about secrets** - If unsure, redact it
4. **Consider worst-case scenarios** - What if a competitor reads this?
5. **Ask "would I want this public?"** - If no, reject

### For Publishers

1. **Final review before publish** - One last read-through
2. **Verify blog platform is ready** - Test access before publishing
3. **Have rollback plan** - Know how to unpublish if needed
4. **Monitor after publishing** - Watch for community reactions
5. **Alert security team if issues** - Immediately report any concerns

## Troubleshooting

### Publishing Blocked: "Secrets detected"

**Cause**: Final secret scan detected secrets in approved draft.

**Fix**:
1. Review which secrets were detected (check logs)
2. Update draft content to remove/redact secrets
3. Regenerate draft
4. Re-submit for approval
5. Re-attempt publishing

### Publishing Blocked: "Status is not approved"

**Cause**: Draft hasn't been approved yet.

**Fix**:
1. Verify draft status: `getDraft(draftId).status`
2. If status is 'draft', mark ready for review first
3. If status is 'ready_for_review', get reviewer to approve
4. If status is 'rejected', address rejection reason and resubmit

### No Authorized Publishers

**Cause**: `authorized_publishers` list in `rbac-config.yaml` is empty.

**Fix**:
1. Add Discord user IDs to `authorized_publishers` in config
2. Keep list to 1-2 people (CTO, Head of Marketing)
3. Test by attempting to publish

## Security Notes

- ⚠️ **NEVER set `auto_publish: true`** - This is a catastrophic security risk
- ⚠️ **Keep publisher list minimal** - 1-2 people maximum
- ⚠️ **All operations are logged** - Audit trail for compliance
- ⚠️ **Secrets block publishing** - Cannot override security checks
- ⚠️ **Manual review is mandatory** - No shortcuts or bypasses

## Future Enhancements

Potential improvements for the workflow:

1. **Discord Integration** - Notify reviewers when drafts ready
2. **Web Dashboard** - UI for reviewing/approving drafts
3. **Diff View** - Show changes between draft versions
4. **External Blog Platform Integration** - Auto-post to Mirror/Paragraph after manual approval
5. **Legal Review Integration** - Add legal review step for sensitive topics
6. **A/B Testing** - Test draft variations before publishing
7. **Scheduled Publishing** - Approve now, publish at scheduled time
8. **Rollback Feature** - Quick unpublish if issues detected

---

**Remember**: The goal is to prevent irreversible exposure of sensitive information to the public internet. When in doubt, DON'T PUBLISH.
