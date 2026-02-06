import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { FileWatcher } from "../identity/file-watcher.js";
import { IdentityLoader, createIdentityLoader } from "../identity/identity-loader.js";

// ── Temp Directory ─────────────────────────────────────────

let tmpDir: string;

beforeEach(() => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "identity-test-"));
});

afterEach(() => {
  fs.rmSync(tmpDir, { recursive: true, force: true });
});

// ── Sample BEAUVOIR.md ─────────────────────────────────────

const SAMPLE_BEAUVOIR = `# BEAUVOIR

**Version**: 1.0.0
**Last Updated**: 2026-02-06

## Core Principles

### 1. Understand Before Acting

**Take time to read existing code before modifying it.**

**In practice**: Read at least 3 relevant files before writing code.

### 2. Safety First

**Validate inputs and handle errors gracefully.**

**In practice**: Always use parameterized queries.

## Boundaries

### What I Won't Do

- **Skip tests**: Writing code without tests is not acceptable
- **Force push**: Never force-push to shared branches

### What I Always Do

- **Run tests**: Before committing, ensure all tests pass
- **Sign commits**: DCO sign-off on every commit

## Interaction Style

### Concise

Keep responses brief and focused.

### Opinionated

Recommend best practices proactively.

## Recovery Protocol

When a session starts:

\`\`\`
1. Read BEAUVOIR.md
2. Check NOTES.md
3. Resume context
\`\`\`
`;

describe("IdentityLoader", () => {
  it("loads and parses a BEAUVOIR.md document", async () => {
    const beauvoirPath = path.join(tmpDir, "BEAUVOIR.md");
    const notesPath = path.join(tmpDir, "NOTES.md");
    fs.writeFileSync(beauvoirPath, SAMPLE_BEAUVOIR);

    const loader = new IdentityLoader({ beauvoirPath, notesPath });
    const identity = await loader.load();

    expect(identity.version).toBe("1.0.0");
    expect(identity.lastUpdated).toBe("2026-02-06");
    expect(identity.checksum).toHaveLength(16);

    // Principles
    expect(identity.corePrinciples).toHaveLength(2);
    expect(identity.corePrinciples[0].name).toBe("Understand Before Acting");
    expect(identity.corePrinciples[0].id).toBe(1);

    // Boundaries
    expect(identity.boundaries).toHaveLength(2);
    const willNot = identity.boundaries.find((b) => b.type === "will_not");
    expect(willNot!.items.length).toBeGreaterThanOrEqual(2);

    // Interaction style
    expect(identity.interactionStyle).toContain("Concise");
    expect(identity.interactionStyle).toContain("Opinionated");

    // Recovery protocol
    expect(identity.recoveryProtocol).toContain("Read BEAUVOIR.md");
  });

  it("detects changes on disk via hasChanged()", async () => {
    const beauvoirPath = path.join(tmpDir, "BEAUVOIR.md");
    const notesPath = path.join(tmpDir, "NOTES.md");
    fs.writeFileSync(beauvoirPath, SAMPLE_BEAUVOIR);

    const loader = new IdentityLoader({ beauvoirPath, notesPath });
    await loader.load();

    expect(await loader.hasChanged()).toBe(false);

    // Modify the file
    fs.writeFileSync(beauvoirPath, SAMPLE_BEAUVOIR + "\n## New Section\n");
    expect(await loader.hasChanged()).toBe(true);
  });

  it("keeps previous state on corrupt file during watch callback", async () => {
    const beauvoirPath = path.join(tmpDir, "BEAUVOIR.md");
    const notesPath = path.join(tmpDir, "NOTES.md");
    fs.writeFileSync(beauvoirPath, SAMPLE_BEAUVOIR);

    const loader = new IdentityLoader({ beauvoirPath, notesPath });
    const first = await loader.load();

    expect(first.version).toBe("1.0.0");

    // Write corrupt content then try to load — should throw but getIdentity keeps previous
    fs.unlinkSync(beauvoirPath);
    try {
      await loader.load();
    } catch {
      // Expected — file deleted
    }

    // Previous state preserved
    const identity = loader.getIdentity();
    expect(identity).not.toBeNull();
    expect(identity!.version).toBe("1.0.0");
  });

  it("validates document structure", async () => {
    const beauvoirPath = path.join(tmpDir, "BEAUVOIR.md");
    const notesPath = path.join(tmpDir, "NOTES.md");

    // Minimal document (missing sections)
    fs.writeFileSync(beauvoirPath, "# BEAUVOIR\n\n**Version**: 0.1.0\n");

    const loader = new IdentityLoader({ beauvoirPath, notesPath });
    await loader.load();

    const { valid, issues } = loader.validate();
    expect(valid).toBe(false);
    expect(issues.length).toBeGreaterThan(0);
  });
});

describe("FileWatcher", () => {
  it("debounces rapid changes into single callback", async () => {
    const filePath = path.join(tmpDir, "watched.txt");
    fs.writeFileSync(filePath, "initial");

    const calls: string[] = [];
    const watcher = new FileWatcher({
      filePath,
      debounceMs: 100,
      forcePolling: true,
      pollIntervalMs: 50,
    });

    watcher.start((f) => {
      calls.push(f);
    });

    // Rapid-fire changes
    fs.writeFileSync(filePath, "change-1");
    await new Promise((r) => setTimeout(r, 20));
    fs.writeFileSync(filePath, "change-2");
    await new Promise((r) => setTimeout(r, 20));
    fs.writeFileSync(filePath, "change-3");

    // Wait for debounce + poll interval
    await new Promise((r) => setTimeout(r, 300));

    watcher.stop();

    // Should coalesce into <= 2 callbacks (debounce)
    expect(calls.length).toBeLessThanOrEqual(2);
    expect(calls.length).toBeGreaterThanOrEqual(1);
  });
});
