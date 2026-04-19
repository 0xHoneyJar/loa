import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { writeFileSync, mkdirSync, rmSync, existsSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import {
  loadPersona,
  discoverPersonas,
  parsePersonaFrontmatter,
  readPersonaTitle,
  traceResolution,
  formatResolutionTrace,
  type PersonaResolutionStep,
} from "../main.js";
import type { BridgebuilderConfig } from "../core/types.js";

function mockConfig(overrides?: Partial<BridgebuilderConfig>): BridgebuilderConfig {
  return {
    repos: [{ owner: "test", repo: "repo" }],
    model: "claude-sonnet-4-5-20250929",
    maxPrs: 10,
    maxFilesPerPr: 50,
    maxDiffBytes: 100_000,
    maxInputTokens: 100_000,
    maxOutputTokens: 4096,
    dimensions: ["correctness"],
    reviewMarker: "bridgebuilder-review",
    repoOverridePath: "grimoires/bridgebuilder/BEAUVOIR.md",
    dryRun: false,
    excludePatterns: [],
    sanitizerMode: "default" as const,
    maxRuntimeMinutes: 30,
    reviewMode: "single-pass" as const,
    ...overrides,
  };
}

// --- discoverPersonas ---

describe("discoverPersonas", () => {
  it("discovers available persona packs", async () => {
    const packs = await discoverPersonas();
    assert.ok(packs.includes("default"), "Should include default");
    assert.ok(packs.includes("security"), "Should include security");
    assert.ok(packs.includes("dx"), "Should include dx");
    assert.ok(packs.includes("architecture"), "Should include architecture");
    assert.ok(packs.includes("quick"), "Should include quick");
  });

  it("returns sorted pack names", async () => {
    const packs = await discoverPersonas();
    const sorted = [...packs].sort();
    assert.deepEqual(packs, sorted);
  });

  it("returns exactly 5 packs", async () => {
    const packs = await discoverPersonas();
    assert.equal(packs.length, 5);
  });
});

// --- loadPersona ---

describe("loadPersona", () => {
  it("loads default persona when no persona specified", async () => {
    const config = mockConfig({ persona: undefined });
    // repoOverridePath points to non-existent repo override, falls through to default
    config.repoOverridePath = "/nonexistent/BEAUVOIR.md";
    const result = await loadPersona(config);

    assert.equal(result.source, "pack:default");
    assert.ok(result.content.includes("Bridgebuilder"), "Should contain persona content");
  });

  it("loads named persona pack via config.persona", async () => {
    const config = mockConfig({ persona: "security" });
    const result = await loadPersona(config);

    assert.equal(result.source, "pack:security");
    assert.ok(result.content.includes("security"), "Should contain security persona content");
  });

  it("loads quick persona", async () => {
    const config = mockConfig({ persona: "quick" });
    const result = await loadPersona(config);

    assert.equal(result.source, "pack:quick");
    assert.ok(result.content.includes("triage"), "Should contain quick persona content");
  });

  it("loads dx persona", async () => {
    const config = mockConfig({ persona: "dx" });
    const result = await loadPersona(config);

    assert.equal(result.source, "pack:dx");
    assert.ok(result.content.includes("developer"), "Should contain dx persona content");
  });

  it("loads architecture persona", async () => {
    const config = mockConfig({ persona: "architecture" });
    const result = await loadPersona(config);

    assert.equal(result.source, "pack:architecture");
    assert.ok(result.content.includes("architect"), "Should contain architecture persona content");
  });

  it("throws for unknown persona with available list", async () => {
    const config = mockConfig({ persona: "nonexistent" });
    await assert.rejects(
      () => loadPersona(config),
      (err: Error) => {
        assert.ok(err.message.includes('Unknown persona "nonexistent"'));
        assert.ok(err.message.includes("Available:"));
        assert.ok(err.message.includes("default"));
        assert.ok(err.message.includes("security"));
        return true;
      },
    );
  });

  describe("repo override warning", () => {
    let tmpDir: string;

    beforeEach(() => {
      tmpDir = join(tmpdir(), `persona-test-${Date.now()}-${Math.random().toString(36).slice(2)}`);
      mkdirSync(tmpDir, { recursive: true });
    });

    afterEach(() => {
      if (existsSync(tmpDir)) {
        rmSync(tmpDir, { recursive: true, force: true });
      }
    });

    it("warns when CLI persona overrides existing repo override", async () => {
      const repoOverridePath = join(tmpDir, "BEAUVOIR.md");
      writeFileSync(repoOverridePath, "# Repo Override Persona\nCustom content.");

      const config = mockConfig({
        persona: "security",
        repoOverridePath: repoOverridePath,
      });

      const warnings: string[] = [];
      const logger = { warn: (msg: string) => warnings.push(msg) };

      const result = await loadPersona(config, logger);

      assert.equal(result.source, "pack:security");
      assert.equal(warnings.length, 1);
      assert.ok(warnings[0].includes("--persona security"));
      assert.ok(warnings[0].includes("ignored"));
    });
  });

  describe("custom persona_path", () => {
    let tmpDir: string;

    beforeEach(() => {
      tmpDir = join(tmpdir(), `persona-custom-${Date.now()}-${Math.random().toString(36).slice(2)}`);
      mkdirSync(tmpDir, { recursive: true });
    });

    afterEach(() => {
      if (existsSync(tmpDir)) {
        rmSync(tmpDir, { recursive: true, force: true });
      }
    });

    it("loads custom persona from personaFilePath", async () => {
      const customPath = join(tmpDir, "custom-persona.md");
      writeFileSync(customPath, "# Custom Persona\nCustom review instructions.");

      const config = mockConfig({
        personaFilePath: customPath,
        persona: undefined,
      });
      config.repoOverridePath = "/nonexistent/BEAUVOIR.md";

      const result = await loadPersona(config);

      assert.equal(result.source, `custom:${customPath}`);
      assert.ok(result.content.includes("Custom Persona"));
    });

    it("throws for missing custom persona path", async () => {
      const config = mockConfig({
        personaFilePath: "/nonexistent/custom-persona.md",
        persona: undefined,
      });
      config.repoOverridePath = "/nonexistent/BEAUVOIR.md";

      await assert.rejects(
        () => loadPersona(config),
        /custom path/,
      );
    });

    it("named persona takes precedence over custom path", async () => {
      const customPath = join(tmpDir, "custom.md");
      writeFileSync(customPath, "# Custom");

      const config = mockConfig({
        persona: "security",
        personaFilePath: customPath,
      });

      const result = await loadPersona(config);
      assert.equal(result.source, "pack:security");
    });
  });

  describe("repo-level override", () => {
    let tmpDir: string;

    beforeEach(() => {
      tmpDir = join(tmpdir(), `persona-repo-${Date.now()}-${Math.random().toString(36).slice(2)}`);
      mkdirSync(tmpDir, { recursive: true });
    });

    afterEach(() => {
      if (existsSync(tmpDir)) {
        rmSync(tmpDir, { recursive: true, force: true });
      }
    });

    it("loads repo override when no CLI/YAML persona and no custom path", async () => {
      const repoPath = join(tmpDir, "BEAUVOIR.md");
      writeFileSync(repoPath, "# Repo Override\nCustom repo persona.");

      const config = mockConfig({
        persona: undefined,
        personaFilePath: undefined,
        repoOverridePath: repoPath,
      });

      const result = await loadPersona(config);

      assert.equal(result.source, `repo:${repoPath}`);
      assert.ok(result.content.includes("Repo Override"));
    });
  });

  describe("frontmatter model extraction (V3-2)", () => {
    let tmpDir: string;

    beforeEach(() => {
      tmpDir = join(tmpdir(), `persona-fm-${Date.now()}-${Math.random().toString(36).slice(2)}`);
      mkdirSync(tmpDir, { recursive: true });
    });

    afterEach(() => {
      if (existsSync(tmpDir)) {
        rmSync(tmpDir, { recursive: true, force: true });
      }
    });

    it("extracts model from custom persona with frontmatter", async () => {
      const customPath = join(tmpDir, "model-persona.md");
      writeFileSync(customPath, "---\nmodel: claude-opus-4-6\n---\n# Custom Persona\nContent.");

      const config = mockConfig({
        personaFilePath: customPath,
        persona: undefined,
      });
      config.repoOverridePath = "/nonexistent/BEAUVOIR.md";

      const result = await loadPersona(config);
      assert.equal(result.model, "claude-opus-4-6");
      assert.ok(result.content.includes("# Custom Persona"));
      assert.ok(!result.content.includes("---"));
    });

    it("returns undefined model for persona without frontmatter", async () => {
      const config = mockConfig({ persona: "default" });
      const result = await loadPersona(config);
      assert.equal(result.model, undefined);
    });

    it("returns undefined model when model line is commented out", async () => {
      const customPath = join(tmpDir, "commented.md");
      writeFileSync(customPath, "---\n# model: claude-opus-4-6\n---\n# Persona\nContent.");

      const config = mockConfig({
        personaFilePath: customPath,
        persona: undefined,
      });
      config.repoOverridePath = "/nonexistent/BEAUVOIR.md";

      const result = await loadPersona(config);
      assert.equal(result.model, undefined);
    });

    it("security persona has no active model (commented out)", async () => {
      const config = mockConfig({ persona: "security" });
      const result = await loadPersona(config);
      assert.equal(result.model, undefined);
    });

    it("quick persona has no active model (commented out)", async () => {
      const config = mockConfig({ persona: "quick" });
      const result = await loadPersona(config);
      assert.equal(result.model, undefined);
    });
  });
});

// --- parsePersonaFrontmatter ---

describe("parsePersonaFrontmatter", () => {
  it("returns raw content when no frontmatter", () => {
    const result = parsePersonaFrontmatter("# Persona\nSome content.");
    assert.equal(result.content, "# Persona\nSome content.");
    assert.equal(result.model, undefined);
  });

  it("extracts model from frontmatter", () => {
    const result = parsePersonaFrontmatter("---\nmodel: claude-opus-4-6\n---\n# Persona\nContent.");
    assert.equal(result.content, "# Persona\nContent.");
    assert.equal(result.model, "claude-opus-4-6");
  });

  it("strips quotes from model value", () => {
    const result = parsePersonaFrontmatter('---\nmodel: "claude-opus-4-6"\n---\nContent.');
    assert.equal(result.model, "claude-opus-4-6");
  });

  it("strips single quotes from model value", () => {
    const result = parsePersonaFrontmatter("---\nmodel: 'claude-haiku-4-5'\n---\nContent.");
    assert.equal(result.model, "claude-haiku-4-5");
  });

  it("ignores commented-out model line", () => {
    const result = parsePersonaFrontmatter("---\n# model: claude-opus-4-6\n---\n# Persona\nContent.");
    assert.equal(result.model, undefined);
    assert.equal(result.content, "# Persona\nContent.");
  });

  it("handles frontmatter with no model field", () => {
    const result = parsePersonaFrontmatter("---\nauthor: test\n---\n# Persona\nContent.");
    assert.equal(result.model, undefined);
    assert.equal(result.content, "# Persona\nContent.");
  });

  it("handles empty frontmatter", () => {
    const result = parsePersonaFrontmatter("---\n\n---\n# Persona\nContent.");
    assert.equal(result.model, undefined);
    assert.equal(result.content, "# Persona\nContent.");
  });
});

// --- readPersonaTitle (#396) ---

describe("readPersonaTitle", () => {
  it("extracts the H1 title from a known pack", async () => {
    const title = await readPersonaTitle("default");
    assert.match(title, /Bridgebuilder/);
  });

  it("strips frontmatter before finding H1", async () => {
    // quick.md has a frontmatter model field; title is below
    const title = await readPersonaTitle("quick");
    assert.match(title, /Quick Triage/);
    assert.ok(!title.includes("---"));
    assert.ok(!title.includes("model:"));
  });

  it("falls back to pack name when file missing", async () => {
    const title = await readPersonaTitle("nonexistent-pack");
    assert.equal(title, "nonexistent-pack");
  });
});

// --- traceResolution (#396) ---

describe("traceResolution", () => {
  it("returns 4 steps (L1, L3, L4, L5) always", async () => {
    const steps = await traceResolution(mockConfig());
    assert.equal(steps.length, 4);
    assert.deepEqual(
      steps.map((s) => s.level),
      [1, 3, 4, 5],
    );
  });

  it("marks L1 skip + L5 active when no persona config provided", async () => {
    const steps = await traceResolution(
      mockConfig({ repoOverridePath: "does-not-exist.md" }),
    );
    const [l1, _l3, l4, l5] = steps;
    assert.equal(l1.state, "skip");
    assert.equal(l4.state, "missing");
    assert.equal(l5.state, "active");
  });

  it("marks L1 active + L5 shadow when --persona is set", async () => {
    const steps = await traceResolution(
      mockConfig({ persona: "default", repoOverridePath: "does-not-exist.md" }),
    );
    const [l1, _l3, _l4, l5] = steps;
    assert.equal(l1.state, "active");
    assert.equal(l5.state, "shadow");
  });

  it("marks L1 missing when --persona points at unknown pack", async () => {
    const steps = await traceResolution(
      mockConfig({ persona: "nonexistent", repoOverridePath: "does-not-exist.md" }),
    );
    const l1 = steps[0];
    assert.equal(l1.state, "missing");
    assert.ok(l1.reason?.includes("pack file not found"));
  });

  it("marks L3 active when personaFilePath exists (no L1)", async () => {
    // ESM test files don't have __dirname. Write a tempfile instead.
    const tmpDir = tmpdir();
    const customPath = join(tmpDir, "test-persona-custom.md");
    writeFileSync(customPath, "---\n---\n# Custom Test Persona\n");
    try {
      const steps = await traceResolution(
        mockConfig({
          personaFilePath: customPath,
          repoOverridePath: "does-not-exist.md",
        }),
      );
      const [l1, l3, _l4, l5] = steps;
      assert.equal(l1.state, "skip");
      assert.equal(l3.state, "active");
      assert.equal(l5.state, "shadow");
    } finally {
      rmSync(customPath, { force: true });
    }
  });

  it("marks L3 missing when personaFilePath doesn't exist", async () => {
    const steps = await traceResolution(
      mockConfig({
        personaFilePath: "/nonexistent/custom-persona.md",
        repoOverridePath: "does-not-exist.md",
      }),
    );
    const l3 = steps[1];
    assert.equal(l3.state, "missing");
    assert.ok(l3.reason?.includes("file not found"));
  });
});

// --- formatResolutionTrace (#396) ---

describe("formatResolutionTrace", () => {
  it("starts with header line", () => {
    const steps: PersonaResolutionStep[] = [
      { level: 5, name: "built-in default", state: "active", value: "/path/to/default.md" },
    ];
    const output = formatResolutionTrace(steps);
    assert.match(output, /^persona resolution:/);
  });

  it("includes [active] marker for active level", () => {
    const steps: PersonaResolutionStep[] = [
      { level: 1, name: "--persona flag", state: "active", value: "default" },
    ];
    const output = formatResolutionTrace(steps);
    assert.match(output, /\[active\]/);
  });

  it("includes [shadow] marker for shadowed level", () => {
    const steps: PersonaResolutionStep[] = [
      { level: 1, name: "--persona", state: "active", value: "default" },
      { level: 5, name: "built-in", state: "shadow", value: "/x.md" },
    ];
    const output = formatResolutionTrace(steps);
    assert.match(output, /\[shadow\]/);
  });

  it("includes [missing] marker with reason", () => {
    const steps: PersonaResolutionStep[] = [
      {
        level: 4,
        name: "repo override",
        state: "missing",
        value: "grimoires/x.md",
        reason: "file not found: grimoires/x.md",
      },
    ];
    const output = formatResolutionTrace(steps);
    assert.match(output, /\[missing\]/);
    assert.ok(output.includes("file not found"));
  });

  it("uses [skip] marker for skipped levels", () => {
    const steps: PersonaResolutionStep[] = [
      { level: 1, name: "--persona", state: "skip", reason: "not provided" },
    ];
    const output = formatResolutionTrace(steps);
    assert.match(output, /\[skip\]/);
  });
});
