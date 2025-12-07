import DOMPurify from 'isomorphic-dompurify';
import validator from 'validator';

/**
 * Input Validation and Sanitization
 *
 * SECURITY FIXES:
 * - CRITICAL #3: Comprehensive input validation and sanitization
 * - Prevents XSS, injection attacks, and malicious content
 * - Validates all user inputs before processing
 */

export interface ValidationResult {
  valid: boolean;
  sanitized?: string;
  errors: string[];
}

export interface ContentValidation {
  content: string;
  hasPII: boolean;
  hasXSS: boolean;
  hasInjection: boolean;
  sanitized: string;
  errors: string[];
}

/**
 * Content length limits
 */
export const LIMITS = {
  MESSAGE_LENGTH: 2000, // Discord's limit
  TITLE_LENGTH: 255,
  DESCRIPTION_LENGTH: 50000,
  URL_LENGTH: 2048,
  ATTACHMENT_SIZE: 10 * 1024 * 1024, // 10 MB
  ATTACHMENTS_COUNT: 5,
  URLS_COUNT: 10,
  USERNAME_LENGTH: 100,
  CHANNEL_NAME_LENGTH: 100,
} as const;

/**
 * PII detection patterns
 */
export const PII_PATTERNS = {
  email: /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/g,
  phone: /\b(?:\+?1[-.\s]?)?\(?([0-9]{3})\)?[-.\s]?([0-9]{3})[-.\s]?([0-9]{4})\b/g,
  ssn: /\b\d{3}-\d{2}-\d{4}\b/g,
  creditCard: /\b(?:\d{4}[-\s]?){3}\d{4}\b/g,
  ipAddress: /\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b/g,
  jwt: /\beyJ[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+\.[A-Za-z0-9-_]*\b/g,
  apiKey: /\b(?:api[_-]?key|token|secret)[_-]?[=:]\s*['"]?([a-zA-Z0-9_-]{20,})['"]?/gi,
  password: /\b(?:password|passwd|pwd)[_-]?[=:]\s*['"]?([^\s'"]+)['"]?/gi,
} as const;

/**
 * XSS detection patterns
 */
const XSS_PATTERNS = [
  /<script[^>]*>.*?<\/script>/gi,
  /javascript:/gi,
  /on\w+\s*=/gi, // Event handlers like onclick=
  /<iframe[^>]*>/gi,
  /<object[^>]*>/gi,
  /<embed[^>]*>/gi,
  /<img[^>]*onerror/gi,
] as const;

/**
 * Command injection patterns
 */
const INJECTION_PATTERNS = [
  /[;&|`$(){}[\]<>]/g, // Shell metacharacters
  /\$\([^)]*\)/g, // Command substitution
  /`[^`]*`/g, // Backticks
] as const;

/**
 * Detect PII in text
 */
export function detectPII(text: string): { hasPII: boolean; types: string[] } {
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

/**
 * Redact PII from text
 */
export function redactPII(text: string): string {
  let redacted = text;

  redacted = redacted.replace(PII_PATTERNS.email, '[EMAIL REDACTED]');
  redacted = redacted.replace(PII_PATTERNS.phone, '[PHONE REDACTED]');
  redacted = redacted.replace(PII_PATTERNS.ssn, '[SSN REDACTED]');
  redacted = redacted.replace(PII_PATTERNS.creditCard, '[CARD REDACTED]');
  redacted = redacted.replace(PII_PATTERNS.ipAddress, '[IP REDACTED]');
  redacted = redacted.replace(PII_PATTERNS.jwt, '[TOKEN REDACTED]');
  redacted = redacted.replace(PII_PATTERNS.apiKey, '[API_KEY REDACTED]');
  redacted = redacted.replace(PII_PATTERNS.password, '[PASSWORD REDACTED]');

  return redacted;
}

/**
 * Detect XSS attempts
 */
export function detectXSS(text: string): boolean {
  return XSS_PATTERNS.some(pattern => pattern.test(text));
}

/**
 * Detect command injection attempts
 */
export function detectInjection(text: string): boolean {
  return INJECTION_PATTERNS.some(pattern => pattern.test(text));
}

/**
 * Sanitize HTML/Markdown content
 */
export function sanitizeContent(content: string, options?: { allowMarkdown?: boolean }): string {
  const allowedTags = options?.allowMarkdown
    ? ['b', 'i', 'em', 'strong', 'code', 'pre', 'blockquote', 'a', 'ul', 'ol', 'li']
    : ['b', 'i', 'code', 'pre'];

  const allowedAttributes = options?.allowMarkdown ? { a: ['href'] } : {};

  return DOMPurify.sanitize(content, {
    ALLOWED_TAGS: allowedTags,
    ALLOWED_ATTR: Object.keys(allowedAttributes),
    KEEP_CONTENT: true,
    ALLOW_DATA_ATTR: false,
  });
}

/**
 * Validate and sanitize message content
 */
export function validateMessageContent(content: string): ContentValidation {
  const errors: string[] = [];

  // 1. Length validation
  if (!content || content.trim().length === 0) {
    errors.push('Content cannot be empty');
  }

  if (content.length < 10) {
    errors.push(`Content too short (min 10 characters, got ${content.length})`);
  }

  if (content.length > LIMITS.MESSAGE_LENGTH) {
    errors.push(`Content too long (max ${LIMITS.MESSAGE_LENGTH} characters, got ${content.length})`);
  }

  // 2. PII detection
  const piiCheck = detectPII(content);

  // 3. XSS detection
  const hasXSS = detectXSS(content);
  if (hasXSS) {
    errors.push('Potential XSS attack detected');
  }

  // 4. Injection detection
  const hasInjection = detectInjection(content);
  if (hasInjection) {
    errors.push('Potential command injection detected');
  }

  // 5. Sanitize content
  const sanitized = sanitizeContent(content, { allowMarkdown: true });

  return {
    content,
    hasPII: piiCheck.hasPII,
    hasXSS,
    hasInjection,
    sanitized,
    errors,
  };
}

/**
 * Validate URL
 */
export function validateURL(url: string, allowedDomains?: string[]): ValidationResult {
  const errors: string[] = [];

  // 1. Basic validation
  if (!validator.isURL(url, {
    protocols: ['http', 'https'],
    require_protocol: true,
    require_valid_protocol: true,
  })) {
    errors.push('Invalid URL format');
    return { valid: false, errors };
  }

  // 2. Length check
  if (url.length > LIMITS.URL_LENGTH) {
    errors.push(`URL too long (max ${LIMITS.URL_LENGTH} characters)`);
    return { valid: false, errors };
  }

  // 3. Domain whitelist check
  if (allowedDomains && allowedDomains.length > 0) {
    try {
      const urlObj = new URL(url);
      const isAllowed = allowedDomains.some(domain =>
        urlObj.hostname === domain || urlObj.hostname.endsWith(`.${domain}`)
      );

      if (!isAllowed) {
        errors.push(`Domain not in whitelist: ${urlObj.hostname}`);
        return { valid: false, errors };
      }
    } catch {
      errors.push('Failed to parse URL');
      return { valid: false, errors };
    }
  }

  // 4. Sanitize URL
  const sanitized = validator.escape(url);

  return { valid: true, sanitized, errors: [] };
}

/**
 * Extract and validate URLs from text
 */
export function extractAndValidateURLs(
  text: string,
  allowedDomains?: string[]
): { valid: string[]; invalid: string[] } {
  // Strict URL regex
  const urlRegex = /https?:\/\/(?:www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b(?:[-a-zA-Z0-9()@:%_\+.~#?&\/=]*)/g;
  const urls = text.match(urlRegex) || [];

  const valid: string[] = [];
  const invalid: string[] = [];

  for (const url of urls.slice(0, LIMITS.URLS_COUNT)) {
    const validation = validateURL(url, allowedDomains);
    if (validation.valid && validation.sanitized) {
      valid.push(validation.sanitized);
    } else {
      invalid.push(url);
    }
  }

  return { valid, invalid };
}

/**
 * Validate Discord username/tag
 */
export function validateUsername(username: string): ValidationResult {
  const errors: string[] = [];

  if (!username || username.trim().length === 0) {
    errors.push('Username cannot be empty');
    return { valid: false, errors };
  }

  if (username.length > LIMITS.USERNAME_LENGTH) {
    errors.push(`Username too long (max ${LIMITS.USERNAME_LENGTH} characters)`);
    return { valid: false, errors };
  }

  // Escape HTML entities and special characters
  const sanitized = validator.escape(username);

  return { valid: true, sanitized, errors: [] };
}

/**
 * Validate channel name
 */
export function validateChannelName(channelName: string): ValidationResult {
  const errors: string[] = [];

  if (!channelName || channelName.trim().length === 0) {
    errors.push('Channel name cannot be empty');
    return { valid: false, errors };
  }

  if (channelName.length > LIMITS.CHANNEL_NAME_LENGTH) {
    errors.push(`Channel name too long (max ${LIMITS.CHANNEL_NAME_LENGTH} characters)`);
    return { valid: false, errors };
  }

  const sanitized = validator.escape(channelName);

  return { valid: true, sanitized, errors: [] };
}

/**
 * Validate Linear issue ID
 */
export function validateLinearIssueId(issueId: string): ValidationResult {
  const errors: string[] = [];

  // Linear issue ID format: [A-Z]+-\d+
  const linearIdPattern = /^[A-Z]+-\d+$/;

  if (!linearIdPattern.test(issueId)) {
    errors.push('Invalid Linear issue ID format (expected: ABC-123)');
    return { valid: false, errors };
  }

  return { valid: true, sanitized: issueId, errors: [] };
}

/**
 * Validate attachment
 */
export function validateAttachment(url: string, size: number): ValidationResult {
  const errors: string[] = [];

  // 1. Validate URL
  const urlValidation = validateURL(url);
  if (!urlValidation.valid) {
    errors.push(...urlValidation.errors);
    return { valid: false, errors };
  }

  // 2. Check size
  if (size > LIMITS.ATTACHMENT_SIZE) {
    errors.push(`Attachment too large (max ${LIMITS.ATTACHMENT_SIZE / 1024 / 1024} MB)`);
    return { valid: false, errors };
  }

  // 3. Check file extension
  const allowedExts = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'mp4', 'webm', 'mov', 'pdf', 'txt'];
  const ext = url.split('.').pop()?.toLowerCase();

  if (!ext || !allowedExts.includes(ext)) {
    errors.push(`File type not allowed: ${ext}`);
    return { valid: false, errors };
  }

  return { valid: true, sanitized: urlValidation.sanitized, errors: [] };
}

/**
 * Sanitize object for logging (remove sensitive data)
 */
export function sanitizeForLogging(obj: any): any {
  if (typeof obj === 'string') {
    return redactPII(obj);
  }

  if (Array.isArray(obj)) {
    return obj.map(sanitizeForLogging);
  }

  if (obj && typeof obj === 'object') {
    const sanitized: any = {};
    const sensitiveKeys = ['token', 'password', 'secret', 'apiKey', 'api_key', 'authorization'];

    for (const [key, value] of Object.entries(obj)) {
      const lowerKey = key.toLowerCase();

      if (sensitiveKeys.some(sk => lowerKey.includes(sk))) {
        sanitized[key] = '[REDACTED]';
      } else if (typeof value === 'string') {
        sanitized[key] = redactPII(value);
      } else {
        sanitized[key] = sanitizeForLogging(value);
      }
    }

    return sanitized;
  }

  return obj;
}

/**
 * Rate limit key generator (for user-based rate limiting)
 */
export function getRateLimitKey(userId: string, action: string): string {
  // Validate userId is a Discord snowflake
  if (!/^\d{17,19}$/.test(userId)) {
    throw new Error('Invalid user ID format');
  }

  // Validate action is alphanumeric
  if (!/^[a-z0-9_-]+$/i.test(action)) {
    throw new Error('Invalid action format');
  }

  return `ratelimit:${action}:${userId}`;
}
