/**
 * Input Validation and Length Limits
 *
 * SECURITY FIX (MEDIUM-012): Enforce strict input length limits
 * to prevent DoS and resource exhaustion attacks
 */

import { logger } from './logger';

/**
 * Input validation limits (MEDIUM #12)
 */
export const INPUT_LIMITS = {
  // Discord limits
  MESSAGE_LENGTH: 2000,        // Discord's max message length
  CHANNEL_NAME_LENGTH: 100,    // Discord channel name max
  USERNAME_LENGTH: 32,          // Discord username max

  // Attachment limits
  ATTACHMENT_SIZE: 10 * 1024 * 1024,  // 10 MB
  ATTACHMENTS_COUNT: 5,         // Max attachments per message

  // URL limits
  URLS_COUNT: 10,               // Max URLs to process per message
  URL_LENGTH: 2048,             // Max URL length

  // Linear issue limits
  LINEAR_TITLE_LENGTH: 255,     // Linear issue title max
  LINEAR_DESCRIPTION_LENGTH: 50000,  // Linear description max

  // Command arguments
  COMMAND_ARG_LENGTH: 256,      // Max length for command arguments
  COMMAND_ARGS_COUNT: 10,       // Max number of arguments

  // User preferences
  PREFERENCE_KEY_LENGTH: 64,
  PREFERENCE_VALUE_LENGTH: 1024,
} as const;

/**
 * Validation result
 */
export interface ValidationResult {
  valid: boolean;
  error?: string;
  value?: any;
}

/**
 * Validate message content length
 */
export function validateMessageLength(content: string): ValidationResult {
  if (content.length > INPUT_LIMITS.MESSAGE_LENGTH) {
    return {
      valid: false,
      error: `Message too long (max ${INPUT_LIMITS.MESSAGE_LENGTH} characters)`,
    };
  }

  if (content.length < 1) {
    return {
      valid: false,
      error: 'Message cannot be empty',
    };
  }

  return { valid: true, value: content };
}

/**
 * Validate Linear issue title
 */
export function validateLinearTitle(title: string): ValidationResult {
  const trimmed = title.trim();

  if (trimmed.length === 0) {
    return {
      valid: false,
      error: 'Title cannot be empty',
    };
  }

  if (trimmed.length > INPUT_LIMITS.LINEAR_TITLE_LENGTH) {
    return {
      valid: false,
      error: `Title too long (max ${INPUT_LIMITS.LINEAR_TITLE_LENGTH} characters)`,
    };
  }

  return { valid: true, value: trimmed };
}

/**
 * Validate Linear issue description
 */
export function validateLinearDescription(description: string): ValidationResult {
  if (description.length > INPUT_LIMITS.LINEAR_DESCRIPTION_LENGTH) {
    return {
      valid: false,
      error: `Description too long (max ${INPUT_LIMITS.LINEAR_DESCRIPTION_LENGTH} characters)`,
    };
  }

  return { valid: true, value: description };
}

/**
 * Validate command arguments
 */
export function validateCommandArgs(args: string[]): ValidationResult {
  if (args.length > INPUT_LIMITS.COMMAND_ARGS_COUNT) {
    return {
      valid: false,
      error: `Too many arguments (max ${INPUT_LIMITS.COMMAND_ARGS_COUNT})`,
    };
  }

  for (const arg of args) {
    if (arg.length > INPUT_LIMITS.COMMAND_ARG_LENGTH) {
      return {
        valid: false,
        error: `Argument too long (max ${INPUT_LIMITS.COMMAND_ARG_LENGTH} characters)`,
      };
    }
  }

  return { valid: true, value: args };
}

/**
 * Validate attachment size and count
 */
export function validateAttachments(attachments: any[]): ValidationResult {
  if (attachments.length > INPUT_LIMITS.ATTACHMENTS_COUNT) {
    return {
      valid: false,
      error: `Too many attachments (max ${INPUT_LIMITS.ATTACHMENTS_COUNT})`,
    };
  }

  for (const attachment of attachments) {
    if (attachment.size > INPUT_LIMITS.ATTACHMENT_SIZE) {
      return {
        valid: false,
        error: `Attachment too large: ${attachment.name} (max ${INPUT_LIMITS.ATTACHMENT_SIZE / 1024 / 1024}MB)`,
      };
    }
  }

  return { valid: true, value: attachments };
}

/**
 * Validate URL
 */
export function validateUrl(url: string): ValidationResult {
  if (url.length > INPUT_LIMITS.URL_LENGTH) {
    return {
      valid: false,
      error: `URL too long (max ${INPUT_LIMITS.URL_LENGTH} characters)`,
    };
  }

  // Basic URL format validation
  try {
    new URL(url);
  } catch {
    return {
      valid: false,
      error: 'Invalid URL format',
    };
  }

  // Whitelist protocols
  const allowedProtocols = ['http:', 'https:'];
  const urlObj = new URL(url);
  if (!allowedProtocols.includes(urlObj.protocol)) {
    return {
      valid: false,
      error: 'Only HTTP/HTTPS URLs allowed',
    };
  }

  return { valid: true, value: url };
}

/**
 * Sanitize string for safe storage/display
 */
export function sanitizeString(input: string, maxLength?: number): string {
  let sanitized = input.trim();

  // Remove null bytes
  sanitized = sanitized.replace(/\0/g, '');

  // Truncate if needed
  if (maxLength && sanitized.length > maxLength) {
    sanitized = sanitized.slice(0, maxLength);
  }

  return sanitized;
}

/**
 * Log validation failure
 */
export function logValidationFailure(
  context: string,
  field: string,
  error: string,
  userId?: string
): void {
  logger.warn('Input validation failed', {
    context,
    field,
    error,
    userId,
  });
}
