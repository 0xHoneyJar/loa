/**
 * Tests for Beads Security Validation
 *
 * @module beads/__tests__/validation
 */

import { describe, it, expect } from "vitest";
import {
  BEAD_ID_PATTERN,
  MAX_BEAD_ID_LENGTH,
  MAX_STRING_LENGTH,
  LABEL_PATTERN,
  MAX_LABEL_LENGTH,
  ALLOWED_TYPES,
  ALLOWED_OPERATIONS,
  validateBeadId,
  validateLabel,
  validateType,
  validateOperation,
  validatePriority,
  validatePath,
  shellEscape,
  validateBrCommand,
  safeType,
  safePriority,
  filterValidLabels,
} from "../validation";

// =============================================================================
// Test Data
// =============================================================================

/**
 * SECURITY: Known injection payloads that must be rejected
 */
const INJECTION_PAYLOADS = [
  "../../../etc/passwd",
  "task; rm -rf /",
  "task`whoami`",
  "task$(cat /etc/shadow)",
  "task'; DROP TABLE issues;--",
  "task\nrm -rf /",
  "task\0nullbyte",
  "task|cat /etc/passwd",
  "task&&whoami",
  "task||true",
  "task>>/etc/passwd",
  "task<script>alert(1)</script>",
  "${IFS}cat${IFS}/etc/passwd",
  "task$(id)",
  "task`id`",
];

/**
 * Valid bead IDs that should pass validation
 */
const VALID_BEAD_IDS = [
  "task-123",
  "feature_456",
  "BUG-789",
  "sprint-1-task-2",
  "a",
  "A",
  "0",
  "abc123",
  "ABC_DEF-123",
  "a".repeat(128), // max length
];

/**
 * Invalid bead IDs that should fail validation
 */
const INVALID_BEAD_IDS = [
  "",
  " ",
  "task 123", // space
  "task.123", // dot
  "task/123", // slash
  "task\\123", // backslash
  "task:123", // colon (valid in labels, not in IDs)
  "task@123", // at sign
  "task#123", // hash
  "task$123", // dollar
  "task%123", // percent
  "task^123", // caret
  "task&123", // ampersand
  "task*123", // asterisk
  "task(123)", // parens
  "task+123", // plus
  "task=123", // equals
  "task[123]", // brackets
  "task{123}", // braces
  "task'123", // single quote
  'task"123', // double quote
  "task<123>", // angle brackets
  "task?123", // question mark
  "task!123", // exclamation
  "a".repeat(129), // exceeds max length
];

// =============================================================================
// Pattern Tests
// =============================================================================

describe("BEAD_ID_PATTERN", () => {
  it("should match valid alphanumeric IDs", () => {
    expect(BEAD_ID_PATTERN.test("task123")).toBe(true);
    expect(BEAD_ID_PATTERN.test("TASK")).toBe(true);
    expect(BEAD_ID_PATTERN.test("task_123")).toBe(true);
    expect(BEAD_ID_PATTERN.test("task-123")).toBe(true);
  });

  it("should reject IDs with special characters", () => {
    expect(BEAD_ID_PATTERN.test("task 123")).toBe(false);
    expect(BEAD_ID_PATTERN.test("task.123")).toBe(false);
    expect(BEAD_ID_PATTERN.test("task/123")).toBe(false);
    expect(BEAD_ID_PATTERN.test("task;123")).toBe(false);
  });
});

describe("LABEL_PATTERN", () => {
  it("should match valid labels with colons", () => {
    expect(LABEL_PATTERN.test("sprint:in_progress")).toBe(true);
    expect(LABEL_PATTERN.test("run:current")).toBe(true);
    expect(LABEL_PATTERN.test("session:abc123")).toBe(true);
  });

  it("should reject labels with spaces or special chars", () => {
    expect(LABEL_PATTERN.test("label with spaces")).toBe(false);
    expect(LABEL_PATTERN.test("label;injection")).toBe(false);
    expect(LABEL_PATTERN.test("label$var")).toBe(false);
  });
});

// =============================================================================
// validateBeadId Tests
// =============================================================================

describe("validateBeadId", () => {
  describe("valid inputs", () => {
    it.each(VALID_BEAD_IDS)("should accept valid beadId: %s", (beadId) => {
      expect(() => validateBeadId(beadId)).not.toThrow();
    });
  });

  describe("invalid inputs", () => {
    it.each(INVALID_BEAD_IDS)("should reject invalid beadId: %s", (beadId) => {
      expect(() => validateBeadId(beadId)).toThrow();
    });
  });

  describe("SECURITY: injection payloads", () => {
    it.each(INJECTION_PAYLOADS)(
      "should reject injection payload: %s",
      (payload) => {
        expect(() => validateBeadId(payload)).toThrow();
      },
    );
  });

  describe("type checking", () => {
    it("should reject null", () => {
      expect(() => validateBeadId(null)).toThrow("must be a non-empty string");
    });

    it("should reject undefined", () => {
      expect(() => validateBeadId(undefined)).toThrow(
        "must be a non-empty string",
      );
    });

    it("should reject numbers", () => {
      expect(() => validateBeadId(123)).toThrow("must be a non-empty string");
    });

    it("should reject objects", () => {
      expect(() => validateBeadId({ id: "task" })).toThrow(
        "must be a non-empty string",
      );
    });

    it("should reject arrays", () => {
      expect(() => validateBeadId(["task"])).toThrow(
        "must be a non-empty string",
      );
    });
  });

  describe("length limits", () => {
    it("should accept beadId at max length", () => {
      const maxLengthId = "a".repeat(MAX_BEAD_ID_LENGTH);
      expect(() => validateBeadId(maxLengthId)).not.toThrow();
    });

    it("should reject beadId exceeding max length", () => {
      const tooLongId = "a".repeat(MAX_BEAD_ID_LENGTH + 1);
      expect(() => validateBeadId(tooLongId)).toThrow("exceeds maximum length");
    });
  });
});

// =============================================================================
// validateLabel Tests
// =============================================================================

describe("validateLabel", () => {
  it("should accept valid labels", () => {
    expect(() => validateLabel("sprint:in_progress")).not.toThrow();
    expect(() => validateLabel("run:current")).not.toThrow();
    expect(() => validateLabel("circuit-breaker")).not.toThrow();
    expect(() => validateLabel("same-issue-3x")).not.toThrow();
  });

  it("should reject labels with spaces", () => {
    expect(() => validateLabel("label with spaces")).toThrow();
  });

  it("should reject labels with shell metacharacters", () => {
    expect(() => validateLabel("label;rm")).toThrow();
    expect(() => validateLabel("label$(whoami)")).toThrow();
    expect(() => validateLabel("label`id`")).toThrow();
  });

  it("should reject labels exceeding max length", () => {
    const tooLongLabel = "a".repeat(MAX_LABEL_LENGTH + 1);
    expect(() => validateLabel(tooLongLabel)).toThrow("exceeds maximum length");
  });

  it("should reject non-string inputs", () => {
    expect(() => validateLabel(null)).toThrow();
    expect(() => validateLabel(123)).toThrow();
  });
});

// =============================================================================
// validateType Tests
// =============================================================================

describe("validateType", () => {
  it("should accept all allowed types", () => {
    for (const type of ALLOWED_TYPES) {
      expect(() => validateType(type)).not.toThrow();
    }
  });

  it("should reject unknown types", () => {
    expect(() => validateType("unknown")).toThrow("must be one of");
    expect(() => validateType("TASK")).toThrow(); // case sensitive
  });

  it("should reject non-string inputs", () => {
    expect(() => validateType(null)).toThrow();
    expect(() => validateType(123)).toThrow();
  });
});

// =============================================================================
// validateOperation Tests
// =============================================================================

describe("validateOperation", () => {
  it("should accept all allowed operations", () => {
    for (const op of ALLOWED_OPERATIONS) {
      expect(() => validateOperation(op)).not.toThrow();
    }
  });

  it("should reject unknown operations", () => {
    expect(() => validateOperation("delete")).toThrow("must be one of");
    expect(() => validateOperation("DROP")).toThrow();
  });
});

// =============================================================================
// validatePriority Tests
// =============================================================================

describe("validatePriority", () => {
  it("should accept valid priorities in default range", () => {
    for (let i = 0; i <= 10; i++) {
      expect(() => validatePriority(i)).not.toThrow();
    }
  });

  it("should reject priorities outside default range", () => {
    expect(() => validatePriority(-1)).toThrow("must be between");
    expect(() => validatePriority(11)).toThrow("must be between");
  });

  it("should accept custom range", () => {
    expect(() => validatePriority(5, 1, 5)).not.toThrow();
    expect(() => validatePriority(0, 1, 5)).toThrow();
  });

  it("should reject non-integers", () => {
    expect(() => validatePriority(1.5)).toThrow("must be an integer");
    expect(() => validatePriority("1")).toThrow("must be an integer");
    expect(() => validatePriority(NaN)).toThrow("must be an integer");
  });
});

// =============================================================================
// validatePath Tests
// =============================================================================

describe("validatePath", () => {
  it("should accept valid paths", () => {
    expect(() => validatePath("/home/user/file.txt")).not.toThrow();
    expect(() => validatePath("relative/path")).not.toThrow();
    expect(() => validatePath("file.txt")).not.toThrow();
  });

  describe("SECURITY: path traversal", () => {
    it("should reject paths with ..", () => {
      expect(() => validatePath("../etc/passwd")).toThrow("traversal");
      expect(() => validatePath("/home/../etc/passwd")).toThrow("traversal");
      expect(() => validatePath("..")).toThrow("traversal");
    });

    it("should reject embedded traversal", () => {
      expect(() => validatePath("foo/../bar")).toThrow("traversal");
      expect(() => validatePath("./..")).toThrow("traversal");
    });

    it("should reject URL-encoded traversal", () => {
      expect(() => validatePath("%2e%2e/etc/passwd")).toThrow("encoded traversal");
      expect(() => validatePath("foo/%2e%2e/bar")).toThrow("encoded traversal");
      expect(() => validatePath("%2E%2E")).toThrow("encoded traversal"); // uppercase
      expect(() => validatePath("%2e%2E")).toThrow("encoded traversal"); // mixed case
    });
  });

  describe("SECURITY: null byte injection", () => {
    it("should reject paths with null bytes", () => {
      expect(() => validatePath("file.txt\x00.jpg")).toThrow("null bytes");
      expect(() => validatePath("\x00")).toThrow("null bytes");
    });

    it("should reject paths with URL-encoded null bytes", () => {
      expect(() => validatePath("file.txt%00.jpg")).toThrow("null bytes");
    });
  });

  it("should reject non-string inputs", () => {
    expect(() => validatePath(null)).toThrow();
    expect(() => validatePath(123)).toThrow();
  });
});

// =============================================================================
// shellEscape Tests
// =============================================================================

describe("shellEscape", () => {
  it("should wrap simple strings in single quotes", () => {
    expect(shellEscape("hello")).toBe("'hello'");
    expect(shellEscape("task-123")).toBe("'task-123'");
  });

  it("should escape single quotes", () => {
    expect(shellEscape("it's")).toBe("'it'\\''s'");
    expect(shellEscape("'quoted'")).toBe("''\\''quoted'\\'''");
  });

  describe("SECURITY: prevents command injection", () => {
    it("should safely escape shell metacharacters", () => {
      // These should all be safe to use in shell commands
      expect(shellEscape("$(rm -rf /)")).toBe("'$(rm -rf /)'");
      expect(shellEscape("`whoami`")).toBe("'`whoami`'");
      expect(shellEscape("foo;bar")).toBe("'foo;bar'");
      expect(shellEscape("foo|bar")).toBe("'foo|bar'");
      expect(shellEscape("foo&&bar")).toBe("'foo&&bar'");
      expect(shellEscape("foo||bar")).toBe("'foo||bar'");
      expect(shellEscape("foo>bar")).toBe("'foo>bar'");
      expect(shellEscape("foo<bar")).toBe("'foo<bar'");
    });

    it("should safely escape newlines and special chars", () => {
      expect(shellEscape("foo\nbar")).toBe("'foo\nbar'");
      expect(shellEscape("foo\tbar")).toBe("'foo\tbar'");
      expect(shellEscape("$HOME")).toBe("'$HOME'");
      expect(shellEscape("${PATH}")).toBe("'${PATH}'");
    });
  });

  it("should reject non-string inputs", () => {
    expect(() => shellEscape(123 as unknown as string)).toThrow(
      "requires a string input",
    );
    expect(() => shellEscape(null as unknown as string)).toThrow();
  });

  it("should reject strings exceeding max length", () => {
    const tooLong = "a".repeat(MAX_STRING_LENGTH + 1);
    expect(() => shellEscape(tooLong)).toThrow("exceeds maximum length");
  });

  it("should accept strings at max length", () => {
    const maxLength = "a".repeat(MAX_STRING_LENGTH);
    expect(() => shellEscape(maxLength)).not.toThrow();
  });

  describe("edge cases", () => {
    it("should handle empty string", () => {
      expect(shellEscape("")).toBe("''");
    });

    it("should handle string of only single quotes", () => {
      expect(shellEscape("'''")).toBe("''\\'''\\'''\\'''");
    });

    it("should handle unicode characters", () => {
      expect(shellEscape("emoji: 😀")).toBe("'emoji: 😀'");
      expect(shellEscape("日本語")).toBe("'日本語'");
    });

    it("should handle control characters", () => {
      expect(shellEscape("line1\r\nline2")).toBe("'line1\r\nline2'");
      expect(shellEscape("tab\there")).toBe("'tab\there'");
    });
  });
});

// =============================================================================
// validateBrCommand Tests
// =============================================================================

describe("validateBrCommand", () => {
  it("should accept 'br'", () => {
    expect(() => validateBrCommand("br")).not.toThrow();
  });

  it("should accept valid absolute paths", () => {
    expect(() => validateBrCommand("/usr/local/bin/br")).not.toThrow();
    expect(() => validateBrCommand("/home/user/.cargo/bin/br")).not.toThrow();
  });

  it("should reject relative paths", () => {
    expect(() => validateBrCommand("./br")).toThrow();
    expect(() => validateBrCommand("../bin/br")).toThrow();
  });

  it("should reject paths with shell metacharacters", () => {
    expect(() => validateBrCommand("/bin/br; whoami")).toThrow();
    expect(() => validateBrCommand("/bin/br$(id)")).toThrow();
    expect(() => validateBrCommand("/bin/br`id`")).toThrow();
    expect(() => validateBrCommand("/bin/br && rm -rf /")).toThrow();
  });

  it("should reject paths with spaces", () => {
    expect(() => validateBrCommand("/Program Files/br")).toThrow();
  });

  it("should reject non-string inputs", () => {
    expect(() => validateBrCommand(null)).toThrow();
    expect(() => validateBrCommand(123)).toThrow();
  });
});

// =============================================================================
// Utility Function Tests
// =============================================================================

describe("safeType", () => {
  it("should return valid types unchanged", () => {
    expect(safeType("task")).toBe("task");
    expect(safeType("epic")).toBe("epic");
    expect(safeType("bug")).toBe("bug");
  });

  it("should return default for invalid types", () => {
    expect(safeType("invalid")).toBe("task");
    expect(safeType(null)).toBe("task");
    expect(safeType(123)).toBe("task");
  });

  it("should use custom fallback", () => {
    expect(safeType("invalid", "epic")).toBe("epic");
  });
});

describe("safePriority", () => {
  it("should return valid priorities unchanged", () => {
    expect(safePriority(0)).toBe(0);
    expect(safePriority(5)).toBe(5);
    expect(safePriority(10)).toBe(10);
  });

  it("should return default for invalid priorities", () => {
    expect(safePriority(-1)).toBe(2);
    expect(safePriority(11)).toBe(2);
    expect(safePriority("5")).toBe(2);
    expect(safePriority(null)).toBe(2);
  });

  it("should use custom fallback", () => {
    expect(safePriority("invalid", 5)).toBe(5);
  });
});

describe("filterValidLabels", () => {
  it("should keep valid labels", () => {
    const labels = ["sprint:in_progress", "run:current", "epic"];
    expect(filterValidLabels(labels)).toEqual([
      "sprint:in_progress",
      "run:current",
      "epic",
    ]);
  });

  it("should filter out invalid labels", () => {
    const labels = ["valid", "has spaces", "valid-2", "has;semicolon"];
    expect(filterValidLabels(labels)).toEqual(["valid", "valid-2"]);
  });

  it("should filter out non-strings", () => {
    const labels = ["valid", 123, null, "valid-2", { label: "obj" }];
    expect(filterValidLabels(labels as unknown[])).toEqual(["valid", "valid-2"]);
  });

  it("should filter out labels exceeding max length", () => {
    const labels = ["short", "a".repeat(MAX_LABEL_LENGTH + 1), "also-short"];
    expect(filterValidLabels(labels)).toEqual(["short", "also-short"]);
  });
});
