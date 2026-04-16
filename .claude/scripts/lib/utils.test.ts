import { describe, it } from "node:test";
import assert from "node:assert/strict";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import { untildify, resolvePath, readSeedPaths } from "./utils";

describe("untildify", () => {
  it("expands ~/foo/bar to HOME/foo/bar", () => {
    const home = process.env.HOME!;
    assert.equal(untildify("~/foo/bar"), `${home}/foo/bar`);
  });

  it("throws if HOME is unset", () => {
    const saved = process.env.HOME;
    delete process.env.HOME;
    try {
      assert.throws(() => untildify("~/foo"), /HOME/);
    } finally {
      if (saved !== undefined) process.env.HOME = saved;
    }
  });

  it("returns non-tilde path unchanged", () => {
    assert.equal(untildify("/absolute/path"), "/absolute/path");
  });

  it("returns relative path unchanged", () => {
    assert.equal(untildify("relative/path"), "relative/path");
  });
});

describe("resolvePath", () => {
  it("produces an absolute path", () => {
    const result = resolvePath("~/foo/bar");
    assert.ok(path.isAbsolute(result));
  });

  it("removes ~/ prefix", () => {
    const result = resolvePath("~/foo/bar");
    assert.ok(!result.includes("~/"));
  });
});

describe("readSeedPaths", () => {
  it("returns 8 paths from fixture with 8 ~/-prefixed lines", () => {
    const tmp = path.join(os.tmpdir(), `seed-test-${Date.now()}.md`);
    const lines = Array.from({ length: 8 }, (_, i) => `~/hivemind/wiki/concepts/file${i}.md`).join("\n");
    fs.writeFileSync(tmp, lines, "utf8");
    try {
      const paths = readSeedPaths(tmp);
      assert.equal(paths.length, 8);
      assert.ok(paths.every((p) => p.startsWith("~/")));
    } finally {
      fs.unlinkSync(tmp);
    }
  });

  it("throws if file is missing", () => {
    assert.throws(() => readSeedPaths("/nonexistent/path/seed.md"), /not found/);
  });

  it("throws if no tilde paths found", () => {
    const tmp = path.join(os.tmpdir(), `seed-empty-${Date.now()}.md`);
    fs.writeFileSync(tmp, "# No paths here\nJust regular content\n", "utf8");
    try {
      assert.throws(() => readSeedPaths(tmp), /No tilde/);
    } finally {
      fs.unlinkSync(tmp);
    }
  });
});
