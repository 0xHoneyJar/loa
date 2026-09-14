import { it } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { cpSync, mkdirSync, mkdtempSync, rmSync, symlinkSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { tmpdir } from "node:os";

const main = new URL("../main.ts", import.meta.url);

it("importing main helpers never starts the CLI", () => {
  // --help makes the old accidental startup harmless while still exposing it:
  // process.exit(0) would prevent the import-completed marker.
  const result = spawnSync(process.execPath, ["--import", "tsx", "--input-type=module", "-e",
    `process.argv = ["node", "import-fixture", "--help"]; await import(${JSON.stringify(main.href)}); console.log("import-completed");`,
  ], { encoding: "utf8" });
  assert.equal(result.status, 0);
  assert.equal(result.stdout.trim(), "import-completed");
  assert.equal(result.stderr, "");
});

it("direct CLI execution still handles --help", () => {
  const result = spawnSync(process.execPath, ["--import", "tsx", fileURLToPath(main), "--help"], { encoding: "utf8" });
  assert.equal(result.status, 0);
  assert.match(result.stdout, /[Uu]sage|[Bb]ridgebuilder/);
});

for (const mounted of [false, true]) {
  it(`BIR-003 real ${mounted ? "mounted" : "physical"} entry executes shipped --help`, () => {
    const temp = mkdtempSync(join(tmpdir(), "bb-entry-"));
    const skill = fileURLToPath(new URL("../../", import.meta.url));
    const framework = join(temp, "framework");
    const consumer = join(temp, "consumer");
    const copiedSkill = join(framework, ".claude/skills/bridgebuilder-review");
    const scripts = join(framework, ".claude/scripts");
    try {
      mkdirSync(copiedSkill, { recursive: true });
      cpSync(join(skill, "dist"), join(copiedSkill, "dist"), { recursive: true });
      cpSync(join(skill, "package.json"), join(copiedSkill, "package.json"));
      mkdirSync(join(copiedSkill, "resources"));
      cpSync(join(skill, "resources/entry.sh"), join(copiedSkill, "resources/entry.sh"));
      symlinkSync(join(skill, "node_modules"), join(copiedSkill, "node_modules"), "dir");
      mkdirSync(join(scripts, "lib"), { recursive: true });
      for (const script of ["bash-version-guard.sh", "lib/env-loader.sh"]) {
        cpSync(resolve(skill, "../../scripts", script), join(scripts, script));
      }
      mkdirSync(join(consumer, ".claude"), { recursive: true });
      symlinkSync(join(framework, ".claude/skills"), join(consumer, ".claude/skills"), "dir");
      symlinkSync(scripts, join(consumer, ".claude/scripts"), "dir");
      const entry = join(mounted ? consumer : framework, ".claude/skills/bridgebuilder-review/resources/entry.sh");
      const result = spawnSync("bash", [entry, "--help"], {
        cwd: consumer, encoding: "utf8",
        env: { HOME: process.env.HOME!, PATH: `${dirname(process.execPath)}:/usr/bin:/bin`, LANG: "C.UTF-8" },
      });
      assert.equal(result.status, 0);
      assert.match(result.stdout, /[Uu]sage|[Bb]ridgebuilder/);
      assert.equal(result.stderr, "");
      const imported = spawnSync(process.execPath, ["--input-type=module", "-e",
        `process.argv = ["node", "import-fixture", "--help"]; await import(${JSON.stringify(
          join(consumer, ".claude/skills/bridgebuilder-review/dist/main.js"),
        )}); console.log("import-completed");`,
      ], { cwd: consumer, encoding: "utf8", env: { HOME: process.env.HOME!, PATH: "/usr/bin:/bin", LANG: "C.UTF-8" } });
      assert.equal(imported.status, 0);
      assert.equal(imported.stdout.trim(), "import-completed");
      assert.equal(imported.stderr, "");
    } finally {
      rmSync(temp, { recursive: true, force: true });
    }
  });
}
