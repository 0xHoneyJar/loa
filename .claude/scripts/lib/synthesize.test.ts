import { describe, it } from "node:test";
import assert from "node:assert/strict";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import { synthesize } from "./synthesize";

const SCHEMA_PATH = path.resolve(process.cwd(), "schemas/page-frontmatter.v0.1.json");

function tmpDir(): string {
  const d = path.join(os.tmpdir(), `synth-test-${Date.now()}-${Math.random().toString(36).slice(2)}`);
  fs.mkdirSync(d, { recursive: true });
  return d;
}

function writeSeedFile(dir: string, name: string, content: string): string {
  const p = path.join(dir, name);
  fs.writeFileSync(p, content, "utf8");
  return p;
}

function makeSeedContent(prefix: string): string {
  const lines: string[] = [];
  for (let i = 1; i <= 30; i++) {
    lines.push(`${prefix} substantive claim line ${i} with enough characters to qualify as meaningful content`);
  }
  return lines.join("\n");
}

describe("synthesize", () => {
  it("produces candidate with >= 5 distinct file:line citations", () => {
    const dir = tmpDir();
    const candidatePath = path.join(dir, "candidate.md");
    try {
      const seed1 = writeSeedFile(dir, "seed1.md", makeSeedContent("alpha memory consolidation tier"));
      const seed2 = writeSeedFile(dir, "seed2.md", makeSeedContent("beta confidence decay kaironic time"));

      // Convert absolute paths to tilde paths
      const home = process.env.HOME!;
      const rel1 = path.relative(home, seed1);
      const rel2 = path.relative(home, seed2);
      const tilde1 = `~/${rel1}`;
      const tilde2 = `~/${rel2}`;

      synthesize([tilde1, tilde2], candidatePath, new Set(), SCHEMA_PATH);

      assert.ok(fs.existsSync(candidatePath));
      const content = fs.readFileSync(candidatePath, "utf8");
      const citationRegex = /\[([^\]]+)\]\((~\/[^\s)]+:\d+)\)/g;
      const found = new Set<string>();
      let m: RegExpExecArray | null;
      while ((m = citationRegex.exec(content)) !== null) found.add(m[2]);
      assert.ok(found.size >= 5, `Expected >= 5 citations, got ${found.size}`);
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  it("throws before reading oracle if oracle path is in seed list", () => {
    const dir = tmpDir();
    const oraclePath = path.join(dir, "oracle.md");
    const candidatePath = path.join(dir, "candidate.md");
    fs.writeFileSync(oraclePath, makeSeedContent("oracle"), "utf8");

    const home = process.env.HOME!;
    const tildeOracle = `~/${path.relative(home, oraclePath)}`;
    const oracleExcluded = new Set([oraclePath]);

    try {
      assert.throws(
        () => synthesize([tildeOracle], candidatePath, oracleExcluded, SCHEMA_PATH),
        /Oracle exclusion/,
      );
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  it("tmp file is absent after successful synthesis (renamed to final)", () => {
    const dir = tmpDir();
    const candidatePath = path.join(dir, "candidate.md");
    try {
      const seed = writeSeedFile(dir, "seed.md", makeSeedContent("memory architecture consolidation tier confidence decay kaironic"));
      const home = process.env.HOME!;
      const tilde = `~/${path.relative(home, seed)}`;
      synthesize([tilde], candidatePath, new Set(), SCHEMA_PATH);
      assert.ok(!fs.existsSync(candidatePath + ".tmp"));
      assert.ok(fs.existsSync(candidatePath));
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  it("produces at least 1 claim group from representative seed", () => {
    const dir = tmpDir();
    const candidatePath = path.join(dir, "candidate.md");
    try {
      const seed = writeSeedFile(dir, "seed.md", makeSeedContent("consolidation memory tier pipeline kaironic confidence decay ebbinghaus"));
      const home = process.env.HOME!;
      const tilde = `~/${path.relative(home, seed)}`;
      synthesize([tilde], candidatePath, new Set(), SCHEMA_PATH);
      const content = fs.readFileSync(candidatePath, "utf8");
      assert.ok(content.includes("##"));
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });
});
