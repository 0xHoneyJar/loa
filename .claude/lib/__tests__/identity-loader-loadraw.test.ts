/**
 * T3.9b — Identity Loader loadRaw() enhancement test.
 */
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { writeFile, mkdir, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { IdentityLoader } from "../persistence/identity/identity-loader.js";

describe("IdentityLoader loadRaw (T3.9b)", () => {
  it("loadRaw() returns raw file content without parsing", async () => {
    const dir = join(tmpdir(), `id-raw-${Date.now()}`);
    await mkdir(dir, { recursive: true });
    const content = "# Raw BEAUVOIR\n\nJust plain text.";
    const beauvoirPath = join(dir, "BEAUVOIR.md");
    await writeFile(beauvoirPath, content, "utf-8");

    try {
      const loader = new IdentityLoader({
        beauvoirPath,
        notesPath: join(dir, "NOTES.md"),
      });
      const raw = await loader.loadRaw();
      assert.equal(raw, content);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });

  it("loadRaw() throws on missing file", async () => {
    const loader = new IdentityLoader({
      beauvoirPath: "/nonexistent/BEAUVOIR.md",
      notesPath: "/nonexistent/NOTES.md",
    });
    await assert.rejects(
      () => loader.loadRaw(),
      (err: Error) => err.message.includes("not found"),
    );
  });

  it("loadRaw() does not affect parsed identity state", async () => {
    const dir = join(tmpdir(), `id-raw-state-${Date.now()}`);
    await mkdir(dir, { recursive: true });
    const beauvoirPath = join(dir, "BEAUVOIR.md");
    await writeFile(beauvoirPath, "raw content", "utf-8");

    try {
      const loader = new IdentityLoader({
        beauvoirPath,
        notesPath: join(dir, "NOTES.md"),
      });
      await loader.loadRaw();
      // getIdentity should still be null since loadRaw doesn't parse
      assert.equal(loader.getIdentity(), null);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});
