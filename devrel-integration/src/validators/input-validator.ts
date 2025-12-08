/**
 * Input Validator
 *
 * Validates and sanitizes user input from Discord bot commands to prevent:
 * - Path traversal attacks (../../../etc/passwd)
 * - Command injection (); rm -rf /)
 * - Absolute path access (/etc/passwd)
 * - Excessive document requests (DoS)
 * - Special character exploitation
 *
 * This implements CRITICAL-002 remediation.
 */

export interface ValidationResult {
  valid: boolean;
  sanitized?: string;
  errors: string[];
  warnings: string[];
}

export interface DocumentPathValidationResult extends ValidationResult {
  resolvedPaths?: string[];
}

export class InputValidator {
  // Configuration
  private readonly MAX_DOCUMENTS_PER_REQUEST = 10;
  private readonly MAX_PATH_LENGTH = 500;
  private readonly ALLOWED_EXTENSIONS = ['.md', '.gdoc'];

  // Dangerous patterns
  private readonly PATH_TRAVERSAL_PATTERNS = [
    /\.\./g,                    // Parent directory references
    /~\//g,                     // Home directory references
    /\0/g,                      // Null bytes
    /%2e%2e/gi,                 // URL-encoded ..
    /%252e%252e/gi,             // Double URL-encoded ..
    /\.\\\./g,                  // Windows-style parent directory
  ];

  private readonly COMMAND_INJECTION_PATTERNS = [
    /[;&|`$(){}[\]]/g,          // Shell metacharacters
    /\n|\r/g,                   // Newlines (can break command parsing)
    /\\/g,                      // Backslashes (escape sequences)
    /<|>/g,                     // Redirection operators
  ];

  private readonly DANGEROUS_PATHS = [
    '/etc/',
    '/var/',
    '/usr/',
    '/bin/',
    '/sbin/',
    '/boot/',
    '/dev/',
    '/proc/',
    '/sys/',
    'C:\\Windows\\',
    'C:\\Program Files\\',
  ];

  /**
   * Validate a single document path
   */
  validateDocumentPath(path: string): ValidationResult {
    const errors: string[] = [];
    const warnings: string[] = [];

    // Basic checks
    if (!path || typeof path !== 'string') {
      errors.push('Document path is required and must be a string');
      return { valid: false, errors, warnings };
    }

    // Trim whitespace
    const trimmed = path.trim();

    // Length check
    if (trimmed.length === 0) {
      errors.push('Document path cannot be empty');
      return { valid: false, errors, warnings };
    }

    if (trimmed.length > this.MAX_PATH_LENGTH) {
      errors.push(`Document path too long (max ${this.MAX_PATH_LENGTH} characters)`);
      return { valid: false, errors, warnings };
    }

    // Absolute path check
    if (this.isAbsolutePath(trimmed)) {
      errors.push('Absolute paths are not allowed (use relative paths only)');
      return { valid: false, errors, warnings };
    }

    // Path traversal check
    for (const pattern of this.PATH_TRAVERSAL_PATTERNS) {
      if (pattern.test(trimmed)) {
        errors.push('Path traversal detected - parent directory references not allowed');
        return { valid: false, errors, warnings };
      }
    }

    // Command injection check
    for (const pattern of this.COMMAND_INJECTION_PATTERNS) {
      if (pattern.test(trimmed)) {
        errors.push('Special characters detected - potential command injection attempt');
        return { valid: false, errors, warnings };
      }
    }

    // Dangerous path check
    for (const dangerousPath of this.DANGEROUS_PATHS) {
      if (trimmed.toLowerCase().includes(dangerousPath.toLowerCase())) {
        errors.push('Access to system directories is not allowed');
        return { valid: false, errors, warnings };
      }
    }

    // Extension check
    const hasValidExtension = this.ALLOWED_EXTENSIONS.some(ext =>
      trimmed.toLowerCase().endsWith(ext)
    );

    if (!hasValidExtension) {
      errors.push(`Only ${this.ALLOWED_EXTENSIONS.join(', ')} files are allowed`);
      return { valid: false, errors, warnings };
    }

    // File name check (no suspicious patterns)
    const fileName = trimmed.split('/').pop() || '';
    if (fileName.startsWith('.')) {
      warnings.push('Hidden files may not be accessible');
    }

    // All checks passed
    return {
      valid: true,
      sanitized: trimmed,
      errors: [],
      warnings
    };
  }

  /**
   * Validate multiple document paths
   */
  validateDocumentPaths(paths: string[]): DocumentPathValidationResult {
    const errors: string[] = [];
    const warnings: string[] = [];
    const resolvedPaths: string[] = [];

    // Check if paths is an array
    if (!Array.isArray(paths)) {
      errors.push('Document paths must be provided as an array');
      return { valid: false, errors, warnings };
    }

    // Empty array check
    if (paths.length === 0) {
      errors.push('At least one document path is required');
      return { valid: false, errors, warnings };
    }

    // Document count limit
    if (paths.length > this.MAX_DOCUMENTS_PER_REQUEST) {
      errors.push(`Too many documents requested (max ${this.MAX_DOCUMENTS_PER_REQUEST} per request)`);
      return { valid: false, errors, warnings };
    }

    // Validate each path
    for (let i = 0; i < paths.length; i++) {
      const result = this.validateDocumentPath(paths[i]);

      if (!result.valid) {
        errors.push(`Document ${i + 1} (${paths[i]}): ${result.errors.join(', ')}`);
      } else {
        if (result.sanitized) {
          resolvedPaths.push(result.sanitized);
        }
        if (result.warnings.length > 0) {
          warnings.push(`Document ${i + 1}: ${result.warnings.join(', ')}`);
        }
      }
    }

    // Check for duplicate paths
    const uniquePaths = new Set(resolvedPaths);
    if (uniquePaths.size < resolvedPaths.length) {
      warnings.push('Duplicate document paths detected - will be processed only once');
      // Remove duplicates
      const deduplicated = Array.from(uniquePaths);
      return {
        valid: errors.length === 0,
        resolvedPaths: deduplicated,
        errors,
        warnings
      };
    }

    return {
      valid: errors.length === 0,
      resolvedPaths,
      errors,
      warnings
    };
  }

  /**
   * Validate Discord command arguments
   */
  validateCommandArgs(command: string, args: string[]): ValidationResult {
    const errors: string[] = [];
    const warnings: string[] = [];

    // Command name validation
    if (!command || typeof command !== 'string') {
      errors.push('Command name is required');
      return { valid: false, errors, warnings };
    }

    const trimmedCommand = command.trim().toLowerCase();

    // Only allow alphanumeric and hyphens in command names
    if (!/^[a-z0-9-]+$/.test(trimmedCommand)) {
      errors.push('Invalid command name - only lowercase letters, numbers, and hyphens allowed');
      return { valid: false, errors, warnings };
    }

    // Args validation
    if (!Array.isArray(args)) {
      errors.push('Command arguments must be an array');
      return { valid: false, errors, warnings };
    }

    // Check each arg for injection attempts
    for (let i = 0; i < args.length; i++) {
      if (typeof args[i] !== 'string') {
        errors.push(`Argument ${i + 1} must be a string`);
        continue;
      }

      const arg = args[i];

      // Check for command injection patterns
      for (const pattern of this.COMMAND_INJECTION_PATTERNS) {
        if (pattern.test(arg)) {
          errors.push(`Argument ${i + 1} contains special characters - potential injection attempt`);
          break;
        }
      }
    }

    return {
      valid: errors.length === 0,
      errors,
      warnings
    };
  }

  /**
   * Validate audience input (for translation requests)
   */
  validateAudience(audience: string): ValidationResult {
    const errors: string[] = [];
    const warnings: string[] = [];

    if (!audience || typeof audience !== 'string') {
      errors.push('Audience is required and must be a string');
      return { valid: false, errors, warnings };
    }

    const trimmed = audience.trim();

    if (trimmed.length === 0) {
      errors.push('Audience cannot be empty');
      return { valid: false, errors, warnings };
    }

    if (trimmed.length > 200) {
      errors.push('Audience description too long (max 200 characters)');
      return { valid: false, errors, warnings };
    }

    // Only allow letters, numbers, spaces, commas, and basic punctuation
    if (!/^[a-zA-Z0-9\s,.\-()]+$/.test(trimmed)) {
      errors.push('Audience contains invalid characters');
      return { valid: false, errors, warnings };
    }

    return {
      valid: true,
      sanitized: trimmed,
      errors: [],
      warnings
    };
  }

  /**
   * Validate format input (for translation requests)
   */
  validateFormat(format: string): ValidationResult {
    const errors: string[] = [];
    const warnings: string[] = [];
    const validFormats = ['executive', 'marketing', 'product', 'engineering', 'unified'];

    if (!format || typeof format !== 'string') {
      errors.push('Format is required and must be a string');
      return { valid: false, errors, warnings };
    }

    const trimmed = format.trim().toLowerCase();

    if (!validFormats.includes(trimmed)) {
      errors.push(`Invalid format. Allowed: ${validFormats.join(', ')}`);
      return { valid: false, errors, warnings };
    }

    return {
      valid: true,
      sanitized: trimmed,
      errors: [],
      warnings
    };
  }

  /**
   * Check if path is absolute
   */
  private isAbsolutePath(path: string): boolean {
    // Unix absolute paths
    if (path.startsWith('/')) {
      return true;
    }

    // Windows absolute paths
    if (/^[a-zA-Z]:\\/.test(path)) {
      return true;
    }

    // UNC paths
    if (path.startsWith('\\\\')) {
      return true;
    }

    return false;
  }

  /**
   * Sanitize a string for safe display (prevent XSS in logs/UI)
   */
  sanitizeForDisplay(input: string): string {
    if (!input || typeof input !== 'string') {
      return '';
    }

    return input
      .replace(/[<>]/g, '') // Remove HTML tags
      .replace(/[&]/g, '&amp;')
      .substring(0, 1000); // Limit length for display
  }
}

export default new InputValidator();
