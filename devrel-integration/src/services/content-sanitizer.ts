/**
 * Content Sanitizer
 *
 * Protects against prompt injection attacks by sanitizing document content
 * before passing to AI agents.
 *
 * Security Controls:
 * - Remove hidden text (white on white, zero-width characters)
 * - Strip system instruction keywords
 * - Detect and block prompt injection attempts
 * - Normalize content to prevent encoding attacks
 */

export interface SanitizationResult {
  sanitized: string;
  removed: string[];
  flagged: boolean;
  reason?: string;
}

export class ContentSanitizer {
  private readonly dangerousPatterns: RegExp[] = [
    // System instruction keywords
    /SYSTEM:/gi,
    /ignore\s+(all\s+)?previous\s+instructions/gi,
    /you\s+are\s+now/gi,
    /new\s+instructions:/gi,
    /disregard\s+(all\s+)?above/gi,
    /forget\s+(all\s+)?previous/gi,
    /override\s+instructions/gi,
    /as\s+an\s+AI\s+assistant/gi,

    // Command injection attempts
    /execute\s+command/gi,
    /run\s+script/gi,
    /eval\(/gi,
    /exec\(/gi,

    // Delimiter confusion attacks
    /```system/gi,
    /\[SYSTEM\]/gi,
    /\<system\>/gi,

    // Role confusion
    /you\s+must/gi,
    /your\s+new\s+role/gi,
    /switch\s+to\s+developer\s+mode/gi,
  ];

  /**
   * Sanitize document content before passing to AI agent
   */
  sanitizeContent(content: string): SanitizationResult {
    const removed: string[] = [];
    let sanitized = content;
    let flagged = false;
    let reason: string | undefined;

    // Step 1: Remove hidden text
    const hiddenTextResult = this.removeHiddenText(sanitized);
    sanitized = hiddenTextResult.text;
    if (hiddenTextResult.removed.length > 0) {
      removed.push(...hiddenTextResult.removed);
      flagged = true;
      reason = 'Hidden text detected and removed';
    }

    // Step 2: Remove dangerous patterns
    for (const pattern of this.dangerousPatterns) {
      const matches = sanitized.match(pattern);
      if (matches) {
        flagged = true;
        reason = reason || 'Prompt injection keywords detected';
        removed.push(...matches);
        sanitized = sanitized.replace(pattern, '[REDACTED]');
      }
    }

    // Step 3: Normalize whitespace and encoding
    sanitized = this.normalizeContent(sanitized);

    // Step 4: Check for excessive instructions
    if (this.hasExcessiveInstructions(sanitized)) {
      flagged = true;
      reason = 'Excessive instructional content detected';
    }

    return {
      sanitized,
      removed,
      flagged,
      reason
    };
  }

  /**
   * Remove hidden text patterns
   */
  private removeHiddenText(content: string): { text: string; removed: string[] } {
    const removed: string[] = [];
    let text = content;

    // Remove zero-width characters
    const zeroWidthChars = [
      '\u200B', // Zero-width space
      '\u200C', // Zero-width non-joiner
      '\u200D', // Zero-width joiner
      '\uFEFF', // Zero-width no-break space
      '\u180E', // Mongolian vowel separator
    ];

    for (const char of zeroWidthChars) {
      if (text.includes(char)) {
        const count = (text.match(new RegExp(char, 'g')) || []).length;
        removed.push(`Zero-width character (U+${char.charCodeAt(0).toString(16).toUpperCase()}) x${count}`);
        text = text.replace(new RegExp(char, 'g'), '');
      }
    }

    // Remove invisible Unicode characters (various spaces)
    const invisibleChars = /[\u00A0\u1680\u2000-\u200A\u202F\u205F\u3000]/g;
    const invisibleMatches = text.match(invisibleChars);
    if (invisibleMatches) {
      removed.push(`Invisible Unicode characters x${invisibleMatches.length}`);
      text = text.replace(invisibleChars, ' ');
    }

    // Detect potential color-based hiding (common patterns in text)
    const colorHidingPatterns = [
      /color:\s*white/gi,
      /color:\s*#fff/gi,
      /color:\s*rgb\(255,\s*255,\s*255\)/gi,
      /opacity:\s*0/gi,
      /font-size:\s*0/gi,
      /display:\s*none/gi,
    ];

    for (const pattern of colorHidingPatterns) {
      if (pattern.test(text)) {
        removed.push(`Potential color-based hiding: ${pattern.source}`);
      }
    }

    return { text, removed };
  }

  /**
   * Normalize content to prevent encoding attacks
   */
  private normalizeContent(content: string): string {
    // Normalize Unicode (convert to NFC form)
    let normalized = content.normalize('NFC');

    // Normalize whitespace (multiple spaces to single space)
    normalized = normalized.replace(/\s+/g, ' ');

    // Trim excessive line breaks (max 2 consecutive)
    normalized = normalized.replace(/\n{3,}/g, '\n\n');

    return normalized.trim();
  }

  /**
   * Check for excessive instructional content
   * (May indicate prompt injection attempt)
   */
  private hasExcessiveInstructions(content: string): boolean {
    const instructionalWords = [
      'must', 'should', 'always', 'never', 'required', 'mandatory',
      'instruction', 'command', 'directive', 'rule', 'policy'
    ];

    const wordCount = content.split(/\s+/).length;
    const instructionCount = instructionalWords.reduce((count, word) => {
      const regex = new RegExp(`\\b${word}\\b`, 'gi');
      return count + (content.match(regex) || []).length;
    }, 0);

    // Flag if >10% of content is instructional keywords
    return instructionCount / wordCount > 0.1;
  }

  /**
   * Validate sanitization was effective
   */
  validateSanitization(original: string, sanitized: string): boolean {
    // Ensure dangerous patterns are removed
    for (const pattern of this.dangerousPatterns) {
      if (pattern.test(sanitized)) {
        return false;
      }
    }

    // Ensure content length is reasonable (not too much removed)
    const removalRatio = 1 - (sanitized.length / original.length);
    if (removalRatio > 0.5) {
      // More than 50% removed - may be too aggressive
      return false;
    }

    return true;
  }
}

export default new ContentSanitizer();
