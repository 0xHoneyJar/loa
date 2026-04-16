import { describe, it } from "node:test";
import assert from "node:assert/strict";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import { runPreflight } from "./preflight";

function captureExit(fn: () => void): number | null {
  let code: number | null = null;
  const mockExit = (c: number): never => {
    code = c;
    throw new Error(`process.exit(${c})`);
  };
  try {
    fn.call(null, mockExit);
  } catch (e: unknown) {
    if (!(e instanceof Error && e.message.startsWith("process.exit"))) throw e;
  }
  return code;
}

describe("preflight", () => {
  it("exits 2 when oracle and candidate paths are identical", () => {
    const tmp = path.join(os.tmpdir(), `oracle-same-${Date.now()}.md`);
    fs.writeFileSync(tmp, "content", "utf8");
    try {
      let code: number | null = null;
      const mockExit = (c: number): never => { code = c; throw new Error(`exit(${c})`); };
      try { runPreflight(tmp, tmp, [], mockExit); } catch {}
      assert.equal(code, 2);
    } finally {
      fs.unlinkSync(tmp);
    }
  });

  it("exits 3 when oracle is not readable", () => {
    const oracle = "/nonexistent/oracle/path.md";
    const candidate = "/tmp/candidate.md";
    let code: number | null = null;
    const mockExit = (c: number): never => { code = c; throw new Error(`exit(${c})`); };
    try { runPreflight(oracle, candidate, [], mockExit); } catch {}
    assert.equal(code, 3);
  });

  it("exits 3 for identical paths regardless of read permissions", () => {
    const nonExistent = "/nonexistent/shared.md";
    let code: number | null = null;
    const mockExit = (c: number): never => { code = c; throw new Error(`exit(${c})`); };
    try { runPreflight(nonExistent, nonExistent, [], mockExit); } catch {}
    assert.equal(code, 2);
  });

  it("exits 1 when a seed file is not readable", () => {
    const oracle = path.join(os.tmpdir(), `oracle-seed-${Date.now()}.md`);
    const candidate = path.join(os.tmpdir(), `cand-seed-${Date.now()}.md`);
    fs.writeFileSync(oracle, "content", "utf8");
    try {
      let code: number | null = null;
      const mockExit = (c: number): never => { code = c; throw new Error(`exit(${c})`); };
      try { runPreflight(oracle, candidate, ["~/nonexistent/seed.md"], mockExit); } catch {}
      assert.equal(code, 1);
    } finally {
      fs.unlinkSync(oracle);
    }
  });

  it("returns normally when all checks pass", () => {
    const oracle = path.join(os.tmpdir(), `oracle-ok-${Date.now()}.md`);
    const candidate = path.join(os.tmpdir(), `cand-ok-${Date.now()}.md`);
    const seed = path.join(os.tmpdir(), `seed-ok-${Date.now()}.md`);
    fs.writeFileSync(oracle, "content", "utf8");
    fs.writeFileSync(seed, "seed content", "utf8");
    try {
      let exited = false;
      const mockExit = (c: number): never => { exited = true; throw new Error(`exit(${c})`); };
      // Use absolute seed path to avoid tilde expansion issues
      const seedTilde = `~/${path.relative(os.homedir(), seed)}`;
      runPreflight(oracle, candidate, [seedTilde], mockExit);
      assert.ok(!exited);
    } finally {
      fs.unlinkSync(oracle);
      if (fs.existsSync(seed)) fs.unlinkSync(seed);
    }
  });
});
