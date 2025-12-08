/**
 * Document Size Validator
 *
 * Implements HIGH-003: Input Length Limits
 * Prevents DoS attacks via unlimited document sizes
 */

export interface Document {
  id: string;
  name: string;
  content: string;
  pageCount?: number;
  sizeBytes?: number;
  url?: string;
}

export interface ValidationResult {
  valid: boolean;
  error?: string;
  details?: {
    currentValue: number;
    maxValue: number;
    metric: string;
  };
}

/**
 * Document size limits to prevent resource exhaustion
 */
export const DOCUMENT_LIMITS = {
  MAX_PAGES: 50,
  MAX_CHARACTERS: 100_000,
  MAX_SIZE_MB: 10,
  MAX_SIZE_BYTES: 10 * 1024 * 1024, // 10 MB
} as const;

/**
 * Digest limits to prevent API timeout and memory exhaustion
 */
export const DIGEST_LIMITS = {
  MAX_DOCUMENTS: 10,
  MAX_TOTAL_CHARACTERS: 500_000, // Total across all documents
} as const;

/**
 * Command input limits
 */
export const INPUT_LIMITS = {
  MAX_COMMAND_LENGTH: 500,
  MAX_PARAMETER_LENGTH: 100,
  MAX_DOCUMENT_NAMES: 3,
} as const;

export class ValidationError extends Error {
  constructor(
    message: string,
    public readonly details?: {
      currentValue: number;
      maxValue: number;
      metric: string;
    }
  ) {
    super(message);
    this.name = 'ValidationError';
  }
}

/**
 * Validates a single document against size limits
 */
export function validateDocumentSize(document: Document): ValidationResult {
  // Check page count if available
  if (document.pageCount !== undefined && document.pageCount > DOCUMENT_LIMITS.MAX_PAGES) {
    return {
      valid: false,
      error: `Document "${document.name}" exceeds maximum ${DOCUMENT_LIMITS.MAX_PAGES} pages`,
      details: {
        currentValue: document.pageCount,
        maxValue: DOCUMENT_LIMITS.MAX_PAGES,
        metric: 'pages',
      },
    };
  }

  // Check character count
  if (document.content.length > DOCUMENT_LIMITS.MAX_CHARACTERS) {
    return {
      valid: false,
      error: `Document "${document.name}" exceeds maximum ${DOCUMENT_LIMITS.MAX_CHARACTERS} characters`,
      details: {
        currentValue: document.content.length,
        maxValue: DOCUMENT_LIMITS.MAX_CHARACTERS,
        metric: 'characters',
      },
    };
  }

  // Check file size if available
  if (document.sizeBytes !== undefined && document.sizeBytes > DOCUMENT_LIMITS.MAX_SIZE_BYTES) {
    const sizeMB = document.sizeBytes / (1024 * 1024);
    return {
      valid: false,
      error: `Document "${document.name}" exceeds maximum ${DOCUMENT_LIMITS.MAX_SIZE_MB}MB (${sizeMB.toFixed(2)}MB)`,
      details: {
        currentValue: document.sizeBytes,
        maxValue: DOCUMENT_LIMITS.MAX_SIZE_BYTES,
        metric: 'bytes',
      },
    };
  }

  return { valid: true };
}

/**
 * Validates a digest (collection of documents) against total size limits
 */
export function validateDigest(documents: Document[]): ValidationResult {
  // Check document count
  if (documents.length > DIGEST_LIMITS.MAX_DOCUMENTS) {
    return {
      valid: false,
      error: `Digest contains ${documents.length} documents, exceeds maximum ${DIGEST_LIMITS.MAX_DOCUMENTS}`,
      details: {
        currentValue: documents.length,
        maxValue: DIGEST_LIMITS.MAX_DOCUMENTS,
        metric: 'documents',
      },
    };
  }

  // Check total character count across all documents
  const totalCharacters = documents.reduce((sum, doc) => sum + doc.content.length, 0);
  if (totalCharacters > DIGEST_LIMITS.MAX_TOTAL_CHARACTERS) {
    return {
      valid: false,
      error: `Digest total size (${totalCharacters} characters) exceeds maximum ${DIGEST_LIMITS.MAX_TOTAL_CHARACTERS}`,
      details: {
        currentValue: totalCharacters,
        maxValue: DIGEST_LIMITS.MAX_TOTAL_CHARACTERS,
        metric: 'total_characters',
      },
    };
  }

  // Validate each individual document
  for (const document of documents) {
    const result = validateDocumentSize(document);
    if (!result.valid) {
      return result;
    }
  }

  return { valid: true };
}

/**
 * Validates command input length
 */
export function validateCommandInput(input: string): ValidationResult {
  if (input.length > INPUT_LIMITS.MAX_COMMAND_LENGTH) {
    return {
      valid: false,
      error: `Command input exceeds maximum ${INPUT_LIMITS.MAX_COMMAND_LENGTH} characters`,
      details: {
        currentValue: input.length,
        maxValue: INPUT_LIMITS.MAX_COMMAND_LENGTH,
        metric: 'characters',
      },
    };
  }

  return { valid: true };
}

/**
 * Validates parameter value length
 */
export function validateParameterLength(paramName: string, value: string): ValidationResult {
  if (value.length > INPUT_LIMITS.MAX_PARAMETER_LENGTH) {
    return {
      valid: false,
      error: `Parameter "${paramName}" exceeds maximum ${INPUT_LIMITS.MAX_PARAMETER_LENGTH} characters`,
      details: {
        currentValue: value.length,
        maxValue: INPUT_LIMITS.MAX_PARAMETER_LENGTH,
        metric: 'characters',
      },
    };
  }

  return { valid: true };
}

/**
 * Validates document name list (e.g., --docs parameter)
 */
export function validateDocumentNames(names: string[]): ValidationResult {
  if (names.length > INPUT_LIMITS.MAX_DOCUMENT_NAMES) {
    return {
      valid: false,
      error: `Too many document names specified (${names.length}), maximum ${INPUT_LIMITS.MAX_DOCUMENT_NAMES}`,
      details: {
        currentValue: names.length,
        maxValue: INPUT_LIMITS.MAX_DOCUMENT_NAMES,
        metric: 'document_names',
      },
    };
  }

  return { valid: true };
}

/**
 * Prioritizes documents by recency when digest exceeds limit
 * Returns the most recent N documents up to MAX_DOCUMENTS
 */
export function prioritizeDocumentsByRecency(
  documents: Document[],
  getLastModified: (doc: Document) => Date
): Document[] {
  if (documents.length <= DIGEST_LIMITS.MAX_DOCUMENTS) {
    return documents;
  }

  // Sort by last modified date (most recent first)
  const sorted = [...documents].sort((a, b) => {
    const dateA = getLastModified(a);
    const dateB = getLastModified(b);
    return dateB.getTime() - dateA.getTime();
  });

  // Return top N most recent
  return sorted.slice(0, DIGEST_LIMITS.MAX_DOCUMENTS);
}

/**
 * Safe validation wrapper that throws ValidationError
 * Use this in service code for cleaner error handling
 */
export function assertValidDocumentSize(document: Document): void {
  const result = validateDocumentSize(document);
  if (!result.valid) {
    throw new ValidationError(result.error!, result.details);
  }
}

export function assertValidDigest(documents: Document[]): void {
  const result = validateDigest(documents);
  if (!result.valid) {
    throw new ValidationError(result.error!, result.details);
  }
}

export function assertValidCommandInput(input: string): void {
  const result = validateCommandInput(input);
  if (!result.valid) {
    throw new ValidationError(result.error!, result.details);
  }
}
