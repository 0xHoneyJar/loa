/**
 * T3.9a — Identity Loader Golden Tests.
 *
 * Captures current observable behavior BEFORE modification.
 * Uses public API: load, getIdentity, getPrinciple, getBoundaries, validate.
 */
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { writeFile, mkdir, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { IdentityLoader } from "../persistence/identity/identity-loader.js";

const SAMPLE_BEAUVOIR = `# BEAUVOIR.md

**Version**: 1.0.0
**Last Updated**: 2026-01-15

## Core Principles

### 1. Safety First

**Protect users above all else**

**In practice**: Never execute destructive operations without confirmation.

### 2. Transparency

**Be honest about limitations**

**In practice**: Clearly state when uncertain about answers.

## Boundaries

### What I Won't Do

1. **Execute harmful code** - Never run malicious payloads
2. **Leak credentials** - Never expose secrets in logs

### What I Always Do

1. **Verify inputs** - Always validate before processing
2. **Log actions** - Always maintain audit trail

## Interaction Style

### Direct Communication

Clear and concise responses.

### Proactive Safety

Warn about risks before they happen.

## Recovery Protocol

When identity is compromised:

\`\`\`
1. Halt all operations
2. Reload from source
3. Verify checksum
\`\`\`
`;

describe("IdentityLoader Golden Tests (T3.9a)", () => {
  let testDir: string;

  async function setup(): Promise<{ beauvoirPath: string; notesPath: string }> {
    testDir = join(tmpdir(), `id-golden-${Date.now()}`);
    await mkdir(testDir, { recursive: true });
    const beauvoirPath = join(testDir, "BEAUVOIR.md");
    const notesPath = join(testDir, "NOTES.md");
    await writeFile(beauvoirPath, SAMPLE_BEAUVOIR, "utf-8");
    await writeFile(notesPath, "# Notes\n", "utf-8");
    return { beauvoirPath, notesPath };
  }

  async function cleanup(): Promise<void> {
    if (testDir) await rm(testDir, { recursive: true, force: true });
  }

  // ── load() ────────────────────────────────────────

  it("load() returns IdentityDocument with parsed fields", async () => {
    const { beauvoirPath, notesPath } = await setup();
    try {
      const loader = new IdentityLoader({ beauvoirPath, notesPath });
      const doc = await loader.load();
      assert.equal(doc.version, "1.0.0");
      assert.equal(doc.lastUpdated, "2026-01-15");
      assert.equal(typeof doc.checksum, "string");
      assert.ok(doc.checksum.length > 0);
    } finally {
      await cleanup();
    }
  });

  it("load() parses core principles", async () => {
    const { beauvoirPath, notesPath } = await setup();
    try {
      const loader = new IdentityLoader({ beauvoirPath, notesPath });
      const doc = await loader.load();
      assert.ok(doc.corePrinciples.length >= 2);
      assert.equal(doc.corePrinciples[0].id, 1);
      assert.equal(doc.corePrinciples[0].name, "Safety First");
    } finally {
      await cleanup();
    }
  });

  it("load() parses boundaries", async () => {
    const { beauvoirPath, notesPath } = await setup();
    try {
      const loader = new IdentityLoader({ beauvoirPath, notesPath });
      const doc = await loader.load();
      assert.ok(doc.boundaries.length >= 2);
      const willNot = doc.boundaries.find((b) => b.type === "will_not");
      assert.ok(willNot);
      assert.ok(willNot!.items.length >= 2);
    } finally {
      await cleanup();
    }
  });

  it("load() throws on missing file", async () => {
    const loader = new IdentityLoader({
      beauvoirPath: "/nonexistent/BEAUVOIR.md",
      notesPath: "/nonexistent/NOTES.md",
    });
    await assert.rejects(
      () => loader.load(),
      (err: Error) => err.message.includes("not found"),
    );
  });

  // ── getIdentity() ─────────────────────────────────

  it("getIdentity() returns null before load", () => {
    const loader = new IdentityLoader({
      beauvoirPath: "/tmp/x",
      notesPath: "/tmp/y",
    });
    assert.equal(loader.getIdentity(), null);
  });

  it("getIdentity() returns document after load", async () => {
    const { beauvoirPath, notesPath } = await setup();
    try {
      const loader = new IdentityLoader({ beauvoirPath, notesPath });
      await loader.load();
      const identity = loader.getIdentity();
      assert.ok(identity !== null);
      assert.equal(identity!.version, "1.0.0");
    } finally {
      await cleanup();
    }
  });

  // ── getPrinciple() ────────────────────────────────

  it("getPrinciple() returns principle by id", async () => {
    const { beauvoirPath, notesPath } = await setup();
    try {
      const loader = new IdentityLoader({ beauvoirPath, notesPath });
      await loader.load();
      const p1 = loader.getPrinciple(1);
      assert.ok(p1);
      assert.equal(p1!.name, "Safety First");
    } finally {
      await cleanup();
    }
  });

  it("getPrinciple() returns undefined for missing id", async () => {
    const { beauvoirPath, notesPath } = await setup();
    try {
      const loader = new IdentityLoader({ beauvoirPath, notesPath });
      await loader.load();
      assert.equal(loader.getPrinciple(999), undefined);
    } finally {
      await cleanup();
    }
  });

  // ── getBoundaries() ───────────────────────────────

  it("getBoundaries() returns will_not items", async () => {
    const { beauvoirPath, notesPath } = await setup();
    try {
      const loader = new IdentityLoader({ beauvoirPath, notesPath });
      await loader.load();
      const items = loader.getBoundaries("will_not");
      assert.ok(items.length >= 2);
    } finally {
      await cleanup();
    }
  });

  it("getBoundaries() returns empty array for unknown type before load", () => {
    const loader = new IdentityLoader({
      beauvoirPath: "/tmp/x",
      notesPath: "/tmp/y",
    });
    assert.deepEqual(loader.getBoundaries("always"), []);
  });

  // ── validate() ────────────────────────────────────

  it("validate() returns invalid before load", () => {
    const loader = new IdentityLoader({
      beauvoirPath: "/tmp/x",
      notesPath: "/tmp/y",
    });
    const result = loader.validate();
    assert.equal(result.valid, false);
    assert.ok(result.issues.includes("Identity not loaded"));
  });

  it("validate() returns valid after loading well-formed document", async () => {
    const { beauvoirPath, notesPath } = await setup();
    try {
      const loader = new IdentityLoader({ beauvoirPath, notesPath });
      await loader.load();
      const result = loader.validate();
      assert.equal(result.valid, true);
      assert.equal(result.issues.length, 0);
    } finally {
      await cleanup();
    }
  });
});
