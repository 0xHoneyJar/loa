import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { PIIRedactor, createPIIRedactor } from "../security/pii-redactor.js";

describe("PIIRedactor", () => {
  // ── Factory ────────────────────────────────────────

  it("createPIIRedactor returns a PIIRedactor instance", () => {
    const redactor = createPIIRedactor();
    assert.ok(redactor instanceof PIIRedactor);
  });

  // ── FR-1.1: Email + Credit Card ────────────────────

  it("FR-1.1: redacts email and credit card", () => {
    const redactor = createPIIRedactor();
    const input = "Contact user@example.com or pay with 4111-1111-1111-1111";
    const { output, matches } = redactor.redact(input);
    assert.ok(!output.includes("user@example.com"));
    assert.ok(!output.includes("4111-1111-1111-1111"));
    assert.ok(output.includes("[REDACTED_EMAIL]"));
    assert.ok(output.includes("[REDACTED_CC]"));
    assert.ok(matches.length >= 2);
  });

  // ── FR-1.2: High Entropy String ────────────────────

  it("FR-1.2: flags 40-char hex string as potential secret", () => {
    const redactor = createPIIRedactor();
    const hex = "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0";
    const input = `token=${hex} done`;
    const { output, matches } = redactor.redact(input);
    // The generic_api_key pattern or entropy should catch this
    const entropyOrKeyMatch = matches.some(
      (m) => m.pattern === "high_entropy" || m.pattern === "generic_api_key",
    );
    assert.ok(entropyOrKeyMatch, "Expected high_entropy or api_key match");
    assert.ok(!output.includes(hex));
  });

  // ── Pattern Coverage ───────────────────────────────

  it("detects SSN pattern", () => {
    const redactor = createPIIRedactor();
    const { output } = redactor.redact("SSN: 123-45-6789");
    assert.ok(output.includes("[REDACTED_SSN]"));
  });

  it("detects US phone number", () => {
    const redactor = createPIIRedactor();
    const { output } = redactor.redact("Call (555) 123-4567");
    assert.ok(output.includes("[REDACTED_PHONE]"));
  });

  it("detects AWS key ID", () => {
    const redactor = createPIIRedactor();
    const { output } = redactor.redact("key: AKIAIOSFODNN7EXAMPLE");
    assert.ok(output.includes("[REDACTED_AWS_KEY]"));
  });

  it("detects GitHub token", () => {
    const redactor = createPIIRedactor();
    // GitHub tokens: ghp_ followed by 36-255 alphanumeric chars
    // Note: "token: ghp_..." also matches generic_api_key which is longer,
    // so use a context that won't trigger generic_api_key
    const token = "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijkl";
    const { output } = redactor.redact(`found ${token} in code`);
    assert.ok(output.includes("[REDACTED_GITHUB_TOKEN]"));
  });

  it("detects IPv4 address", () => {
    const redactor = createPIIRedactor();
    const { output } = redactor.redact("server at 192.168.1.100");
    assert.ok(output.includes("[REDACTED_IP]"));
  });

  it("detects JWT", () => {
    const redactor = createPIIRedactor();
    const jwt =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U";
    const { output } = redactor.redact(`bearer ${jwt}`);
    assert.ok(output.includes("[REDACTED_JWT]"));
  });

  it("detects UUID", () => {
    const redactor = createPIIRedactor();
    const { output } = redactor.redact("id: 550e8400-e29b-41d4-a716-446655440000");
    assert.ok(output.includes("[REDACTED_UUID]"));
  });

  it("detects date of birth pattern", () => {
    const redactor = createPIIRedactor();
    const { output } = redactor.redact("born: 1990-05-15");
    assert.ok(output.includes("[REDACTED_DOB]"));
  });

  it("detects private key header", () => {
    const redactor = createPIIRedactor();
    const { output } = redactor.redact("-----BEGIN RSA PRIVATE KEY-----\ndata");
    assert.ok(output.includes("[REDACTED_PRIVATE_KEY]"));
  });

  it("has 15+ built-in patterns", () => {
    const redactor = createPIIRedactor();
    assert.ok(redactor.getPatterns().length >= 15);
  });

  // ── Edge Cases ─────────────────────────────────────

  it("returns empty input unchanged", () => {
    const redactor = createPIIRedactor();
    const { output, matches } = redactor.redact("");
    assert.equal(output, "");
    assert.equal(matches.length, 0);
  });

  it("returns input unchanged when no matches", () => {
    const redactor = createPIIRedactor();
    const input = "Hello world, this is plain text.";
    const { output, matches } = redactor.redact(input);
    assert.equal(output, input);
    assert.equal(matches.length, 0);
  });

  // ── Custom Patterns ────────────────────────────────

  it("supports custom patterns via constructor", () => {
    const redactor = createPIIRedactor({
      patterns: [
        {
          name: "custom_id",
          regex: /\bCUST-\d{6}\b/g,
          replacement: "[REDACTED_CUSTOM]",
        },
      ],
    });
    const { output } = redactor.redact("Customer CUST-123456 order");
    assert.ok(output.includes("[REDACTED_CUSTOM]"));
  });

  it("supports disabling built-in patterns", () => {
    const redactor = createPIIRedactor({ disabledBuiltins: ["email"] });
    const { output } = redactor.redact("user@example.com");
    // Email should NOT be redacted
    assert.ok(output.includes("user@example.com"));
  });

  it("supports addPattern after construction", () => {
    const redactor = createPIIRedactor();
    redactor.addPattern({
      name: "custom_added",
      regex: /\bADDED-\d+\b/g,
      replacement: "[REDACTED_ADDED]",
    });
    const { output } = redactor.redact("ref ADDED-999");
    assert.ok(output.includes("[REDACTED_ADDED]"));
  });

  // ── Custom pattern without global flag (GPT fix) ───

  it("handles custom patterns without global flag (no infinite loop)", () => {
    const redactor = createPIIRedactor({
      patterns: [
        {
          name: "no_g_flag",
          regex: /\bFOO-\d+\b/, // Note: no 'g' flag
          replacement: "[REDACTED_FOO]",
        },
      ],
    });
    const { output, matches } = redactor.redact("items: FOO-1 and FOO-2");
    assert.ok(output.includes("[REDACTED_FOO]"));
    // Should find both matches even without g flag on the original
    const fooMatches = matches.filter((m) => m.pattern === "no_g_flag");
    assert.equal(fooMatches.length, 2);
  });

  // ── Overlap Resolution ─────────────────────────────

  it("longest match wins when patterns overlap", () => {
    const redactor = createPIIRedactor({
      disabledBuiltins: [
        "email", "ssn", "phone_us", "phone_intl", "credit_card",
        "aws_key_id", "aws_secret", "github_token", "generic_api_key",
        "ipv4", "ipv6", "jwt", "uuid", "date_of_birth", "passport",
        "private_key_header",
      ],
      patterns: [
        { name: "short", regex: /\bABC\b/g, replacement: "[SHORT]" },
        { name: "long", regex: /\bABCDEF\b/g, replacement: "[LONG]" },
      ],
    });
    const { output, matches } = redactor.redact("token ABCDEF end");
    assert.ok(output.includes("[LONG]"));
    assert.ok(!output.includes("[SHORT]"));
    assert.equal(matches.length, 1);
    assert.equal(matches[0].pattern, "long");
  });

  // ── Match Positions ────────────────────────────────

  it("match positions refer to original input", () => {
    const redactor = createPIIRedactor();
    const input = "Email: user@test.com";
    const { matches } = redactor.redact(input);
    const emailMatch = matches.find((m) => m.pattern === "email");
    assert.ok(emailMatch);
    assert.equal(input.slice(emailMatch.position, emailMatch.position + emailMatch.length), "user@test.com");
  });

  // ── FR-7: aws_secret Regex Tightening (cycle-028) ──

  it("does NOT redact SHA-1 hex hashes as aws_secret", () => {
    const redactor = createPIIRedactor();
    const sha1 = "da39a3ee5e6b4b0d3255bfef95601890afd80709";
    const { output, matches } = redactor.redact(`commit: ${sha1}`);
    const awsSecretMatch = matches.some((m) => m.pattern === "aws_secret");
    assert.ok(!awsSecretMatch, "SHA-1 hex hash should NOT be flagged as aws_secret");
    assert.ok(output.includes(sha1) || output.includes("[REDACTED_HIGH_ENTROPY]"),
      "SHA-1 should be preserved or caught only by entropy, not aws_secret");
  });

  it("does NOT redact git commit hashes as aws_secret", () => {
    const redactor = createPIIRedactor();
    const hash = "abc123def456789012345678901234567890abcd";
    const { output, matches } = redactor.redact(`git show ${hash}`);
    const awsSecretMatch = matches.some((m) => m.pattern === "aws_secret");
    assert.ok(!awsSecretMatch, "Git commit hash should NOT be flagged as aws_secret");
  });

  it("does NOT redact uppercase hex-only strings as aws_secret", () => {
    const redactor = createPIIRedactor();
    const hexUpper = "ABCDEF0123456789ABCDEF0123456789ABCDEF01";
    const { matches } = redactor.redact(`checksum: ${hexUpper}`);
    const awsSecretMatch = matches.some((m) => m.pattern === "aws_secret");
    assert.ok(!awsSecretMatch, "Uppercase hex-only string should NOT be flagged as aws_secret");
  });

  it("still detects real AWS secret access keys", () => {
    const redactor = createPIIRedactor();
    // AWS secrets are base64 and always contain non-hex chars (G-Z, /, +, =)
    const awsSecret = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY";
    const { output, matches } = redactor.redact(`secret: ${awsSecret}`);
    // Should be caught by aws_secret or generic_api_key
    const detected = matches.some(
      (m) => m.pattern === "aws_secret" || m.pattern === "generic_api_key",
    );
    assert.ok(detected, "Real AWS secret should be detected");
    assert.ok(!output.includes(awsSecret), "Real AWS secret should be redacted");
  });

  it("aws_key_id pattern still works (AKIA prefix)", () => {
    const redactor = createPIIRedactor();
    const { output } = redactor.redact("key: AKIAIOSFODNN7EXAMPLE");
    assert.ok(output.includes("[REDACTED_AWS_KEY]"), "AWS key ID should still be detected");
  });

  // ── ReDoS Adversarial Regression ───────────────────

  it("completes within 100ms on 10KB adversarial input", () => {
    const redactor = createPIIRedactor();
    // Create adversarial input: near-matches that trigger backtracking in naive patterns
    const adversarial =
      "a".repeat(100) +
      "@" +
      "b".repeat(100) +
      " " +
      "1234-5678-9012-345 ".repeat(200) + // near-CC but 15 digits
      "192.168.1. ".repeat(500) + // near-IP but incomplete
      "ghp_" + "x".repeat(30) + " " + // near-GH token but too short
      "padding ".repeat(200); // ensure ≥10KB

    assert.ok(adversarial.length >= 10000, `Input is ${adversarial.length} bytes`);

    const start = Date.now();
    redactor.redact(adversarial);
    const elapsed = Date.now() - start;
    assert.ok(elapsed < 100, `Took ${elapsed}ms, expected <100ms`);
  });
});
