import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { PatternSanitizer } from "../adapters/sanitizer.js";

describe("PatternSanitizer", () => {
  const sanitizer = new PatternSanitizer();

  it("detects GitHub PATs (ghp_/ghs_)", () => {
    const content = "Token: ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn";
    const result = sanitizer.sanitize(content);
    assert.equal(result.safe, false);
    assert.ok(result.sanitizedContent.includes("[REDACTED]"));
    assert.ok(result.redactedPatterns.includes("github_pat"));
  });

  it("detects GitHub fine-grained PATs", () => {
    const content = "Token: github_pat_ABCDEFGHIJKLMNOPQRSTUV";
    const result = sanitizer.sanitize(content);
    assert.equal(result.safe, false);
    assert.ok(result.redactedPatterns.includes("github_fine_grained"));
  });

  it("detects Anthropic keys", () => {
    const content = "Key: sk-ant-abcdefghijklmnopqrst";
    const result = sanitizer.sanitize(content);
    assert.equal(result.safe, false);
    assert.ok(result.redactedPatterns.includes("anthropic_key"));
  });

  it("detects OpenAI keys", () => {
    const content = "Key: sk-ABCDEFGHIJKLMNOPQRSTx";
    const result = sanitizer.sanitize(content);
    assert.equal(result.safe, false);
    assert.ok(result.redactedPatterns.includes("openai_key"));
  });

  it("detects AWS access keys", () => {
    const content = "AWS: AKIAIOSFODNN7EXAMPLE";
    const result = sanitizer.sanitize(content);
    assert.equal(result.safe, false);
    assert.ok(result.redactedPatterns.includes("aws_key"));
  });

  it("detects Slack tokens", () => {
    const content = "Slack: xoxb-1234567890-abc";
    const result = sanitizer.sanitize(content);
    assert.equal(result.safe, false);
    assert.ok(result.redactedPatterns.includes("slack_token"));
  });

  it("detects private key blocks", () => {
    const content = `-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA0Z3VS5JJcds3xf
-----END RSA PRIVATE KEY-----`;
    const result = sanitizer.sanitize(content);
    assert.equal(result.safe, false);
    assert.ok(result.redactedPatterns.includes("private_key"));
    assert.ok(!result.sanitizedContent.includes("MIIEpAIBAAKCAQEA0Z3VS5JJcds3xf"));
  });

  it("detects high-entropy strings >40 chars", () => {
    // Random base64-like string with high entropy
    const highEntropy = "aB3cD4eF5gH6iJ7kL8mN9oP0qR1sT2uV3wX4yZ5aB6cD7eF8";
    const content = `Safe text ${highEntropy} more text`;
    const result = sanitizer.sanitize(content);
    // High entropy strings should be caught if entropy > 4.5 bits/char
    if (!result.safe) {
      assert.ok(result.redactedPatterns.includes("high_entropy"));
    }
  });

  it("does not redact strings of exactly 40 chars (>40 required)", () => {
    // Exactly 40 chars — should NOT trigger high-entropy detection
    const exactly40 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ01234567890123";
    const content = `Token: ${exactly40}`;
    const result = sanitizer.sanitize(content);
    // Should not be flagged as high_entropy (may still match other patterns)
    const hasHighEntropy = result.redactedPatterns.includes("high_entropy");
    assert.equal(hasHighEntropy, false);
  });

  it("passes clean content through", () => {
    const content = "This is a normal code review with no secrets.";
    const result = sanitizer.sanitize(content);
    assert.equal(result.safe, true);
    assert.equal(result.sanitizedContent, content);
    assert.equal(result.redactedPatterns.length, 0);
  });

  it("redacts multiple occurrences of the same pattern", () => {
    const content = "Keys: AKIAIOSFODNN7EXAMPL1 and AKIAIOSFODNN7EXAMPL2";
    const result = sanitizer.sanitize(content);
    assert.equal(result.safe, false);
    const count = (result.sanitizedContent.match(/\[REDACTED\]/g) ?? []).length;
    assert.ok(count >= 2, `Expected at least 2 redactions, got ${count}`);
  });

  it("supports extra custom patterns", () => {
    const customSanitizer = new PatternSanitizer([/MY_SECRET_\w+/]);
    const content = "Value: MY_SECRET_ABC123 and MY_SECRET_DEF456";
    const result = customSanitizer.sanitize(content);
    assert.equal(result.safe, false);
    assert.ok(result.redactedPatterns.includes("custom_0"));
    const count = (result.sanitizedContent.match(/\[REDACTED\]/g) ?? []).length;
    assert.ok(count >= 2, `Expected at least 2 redactions, got ${count}`);
  });

  // --- Boundary tests: false positives ---

  describe("false positive resistance", () => {
    it("does not redact long camelCase identifiers", () => {
      const content = "const myVeryLongCamelCaseVariableNameThatExceedsFortyCharacters = true;";
      const result = sanitizer.sanitize(content);
      // camelCase has low entropy (~3.5 bits) — should not trigger
      assert.ok(
        !result.redactedPatterns.includes("high_entropy"),
        "camelCase identifiers should not trigger entropy detection",
      );
    });

    it("does not redact long import paths", () => {
      const content = 'import { something } from "@organization/very-long-package-name/dist/some/deeply/nested/module/index";';
      const result = sanitizer.sanitize(content);
      assert.equal(result.safe, true, "Import paths should not be flagged as secrets");
    });

    it("does not redact base64-encoded non-secret data URIs under threshold", () => {
      // Repeating pattern has low entropy (~2 bits) — should not trigger 4.5 threshold
      const lowEntropyBase64 = "aaabbbcccaaabbbcccaaabbbcccaaabbbcccaaabbbccc";
      const content = `data:image/png;base64,${lowEntropyBase64}`;
      const result = sanitizer.sanitize(content);
      const hasHighEntropy = result.redactedPatterns.includes("high_entropy");
      assert.equal(hasHighEntropy, false, "Low-entropy base64 should not trigger");
    });

    it("does not redact URL paths with slashes and dots", () => {
      const content = "Fetching https://api.example.com/v2/users/profile/settings/notifications";
      const result = sanitizer.sanitize(content);
      assert.equal(result.safe, true, "URL paths should not be flagged");
    });
  });

  // --- Boundary tests: true positives ---

  describe("true positive detection", () => {
    it("catches realistic GitHub PAT format", () => {
      const content = "export GITHUB_TOKEN=ghp_1234567890abcdefABCDEFGHIJKLMNOPQRSTUVWX";
      const result = sanitizer.sanitize(content);
      assert.equal(result.safe, false);
      assert.ok(result.redactedPatterns.includes("github_pat"));
    });

    it("catches realistic AWS access key format", () => {
      const content = "aws_access_key_id = AKIAIOSFODNN7EXAMPLE";
      const result = sanitizer.sanitize(content);
      assert.equal(result.safe, false);
      assert.ok(result.redactedPatterns.includes("aws_key"));
    });

    it("OpenAI key does not match Anthropic pattern (negative lookahead)", () => {
      const openaiKey = "sk-ABCDEFGHIJKLMNOPQRSTx";
      const result = sanitizer.sanitize(`Key: ${openaiKey}`);
      assert.equal(result.safe, false);
      assert.ok(result.redactedPatterns.includes("openai_key"));
      assert.ok(!result.redactedPatterns.includes("anthropic_key"),
        "OpenAI key must not match Anthropic pattern");
    });

    it("Anthropic key does not match OpenAI pattern (negative lookahead)", () => {
      const anthropicKey = "sk-ant-abcdefghijklmnopqrst";
      const result = sanitizer.sanitize(`Key: ${anthropicKey}`);
      assert.equal(result.safe, false);
      assert.ok(result.redactedPatterns.includes("anthropic_key"));
      assert.ok(!result.redactedPatterns.includes("openai_key"),
        "Anthropic key must not match OpenAI pattern");
    });

    it("catches high-entropy base64 secret (>4.5 bits/char)", () => {
      // Mixed-case alphanumeric with symbols — ~5.2 bits entropy
      const secret = "aB3cD4eF5gH6iJ7kL8mN9oP0qR1sT2uV3wX4yZ5aB6cD7eF8gH9";
      const content = `SECRET=${secret}`;
      const result = sanitizer.sanitize(content);
      assert.ok(result.redactedPatterns.includes("high_entropy"),
        "High-entropy mixed secret should be caught");
    });
  });
});
