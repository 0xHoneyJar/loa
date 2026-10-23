// cycle-133 Sprint 1 Task 1.2 (sdd.md C-2, FR-2 AC 1, D-1.7 DEC-0853): writer-role eligibility.
//
// The writer may only be an adapter whose no-tool stance is ENFORCED at dispatch: claude-headless (`--tools ""` + plan
// mode) and the HTTP API adapters (no tool definitions on the wire). Every adapter self-reports its stance in the
// dispatch result; the role check verifies that report. codex-headless joins only when a test proves its native tools
// cannot execute under its dispatch — the argv below is a posture, and no unit test can prove the rest, so it stays out.
import { describe, it, mock } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { EventEmitter } from "node:events";
import { PassThrough } from "node:stream";
import type { ChildProcess } from "node:child_process";

import { toolStanceFor, TOOL_STANCE_VERSION } from "../adapters/tool-stance.js";
import { ChevalDelegateAdapter } from "../adapters/cheval-delegate.js";
import {
  checkWriterEligibility, DEFAULT_WRITER_ROLE_ALLOWLIST, effectiveWriterAllowlist, CODEX_WRITER_CAPABILITY_PROOF,
} from "../core/writer-role.js";
import { composeConsensusReview } from "../core/consensus-findings.js";
import { scoreFindings } from "../core/scoring.js";
import { executeMultiModelReview } from "../core/multi-model-pipeline.js";
import type { BridgebuilderConfig, MultiModelConfig, ReviewItem } from "../core/types.js";
import type { PRReviewTemplate } from "../core/template.js";

const REPO = join(import.meta.dirname, "..", "..", "..", "..", "..");
const ADAPTERS = join(REPO, ".claude", "adapters");

/** Run a short stdlib-only Python program against the repo's cheval package (no network, no model call). */
function py(program: string): string {
  return execFileSync("python3", ["-I", "-c", `import sys, json; sys.path.insert(0, ${JSON.stringify(ADAPTERS)})\n${program}`], {
    encoding: "utf8", timeout: 20_000,
  });
}

describe("per-adapter no-tool stance (FR-2 AC 1)", () => {
  it("claude-headless: the dispatched argv disables every tool (`--tools \"\"`) and runs in plan mode", () => {
    const argv = JSON.parse(py("from loa_cheval.providers.claude_headless_adapter import build_headless_argv\nprint(json.dumps(build_headless_argv('claude', 'm')))")) as string[];
    const t = argv.indexOf("--tools");
    assert.ok(t > 0 && argv[t + 1] === "", `--tools "" missing: ${JSON.stringify(argv)}`);
    const p = argv.indexOf("--permission-mode");
    assert.ok(p > 0 && argv[p + 1] === "plan");
    const stance = toolStanceFor("claude-headless");
    assert.deepEqual([stance?.adapter, stance?.tools, stance?.enforced], ["claude-headless", "none", true]);
    assert.deepEqual(checkWriterEligibility(stance, DEFAULT_WRITER_ROLE_ALLOWLIST), { eligible: true });
  });

  it("API adapters (anthropic, openai, google, the bedrock route): cheval builds the request without tools and each adapter sends tools only when the request carries them", () => {
    const cheval = readFileSync(join(ADAPTERS, "cheval.py"), "utf8");
    const ctor = cheval.slice(cheval.indexOf("base_request = CompletionRequest("), cheval.indexOf("base_request = CompletionRequest(") + 1500);
    const ctorBody = ctor.slice(0, ctor.indexOf("\n    )\n"));
    assert.ok(!/\btools\s*=/.test(ctorBody), "the cheval CLI request carries no tool definitions");
    // each API adapter: every tool-definition assignment sits under an `if request.tools:` guard (google sends none)
    for (const [file, expected] of [["anthropic_adapter.py", 2], ["openai_adapter.py", 2], ["google_adapter.py", 0], ["bedrock_adapter.py", 1]] as const) {
      const lines = readFileSync(join(ADAPTERS, "loa_cheval", "providers", file), "utf8").split("\n");
      const sites = lines.flatMap((l, i) => (/body\["(tools|toolConfig)"\]\s*=/.test(l) ? [i] : []));
      assert.equal(sites.length, expected, `${file}: tool-definition assignments`);
      for (const i of sites) assert.match(lines[i - 1], /^\s*if request\.tools:\s*$/, `${file}:${i + 1} sets tools without the request.tools guard`);
    }
    for (const [model, adapter] of [["claude-opus-4-7", "anthropic-api"], ["gpt-5.5-pro", "openai-api"], ["gemini-3.1-pro-preview", "google-api"], ["us.anthropic.claude-haiku-4-5-20251001-v1:0", "bedrock-api"]]) {
      const stance = toolStanceFor(model);
      assert.equal(stance?.adapter, adapter, model);
      assert.deepEqual(checkWriterEligibility(stance, DEFAULT_WRITER_ROLE_ALLOWLIST), { eligible: true }, model);
    }
  });

  it("codex-headless capability test: the argv posture is pinned, but no proof that its native tools cannot execute exists — refused", () => {
    const argv = JSON.parse(py(
      "from types import SimpleNamespace\nfrom loa_cheval.providers.codex_headless_adapter import CodexHeadlessAdapter\n" +
      "from loa_cheval.types import CompletionRequest\na = CodexHeadlessAdapter.__new__(CodexHeadlessAdapter)\n" +
      "print(json.dumps(a._build_command(CompletionRequest(messages=[{'role': 'user', 'content': 'x'}], model='gpt'), SimpleNamespace(extra={}), workspace='/w')))",
    )) as string[];
    // the posture: read-only sandbox, user config ignored, four agent features disabled
    assert.ok(argv.includes("--ignore-user-config"));
    assert.equal(argv[argv.indexOf("--sandbox") + 1], "read-only");
    const disabled = argv.flatMap((a, i) => (a === "--disable" ? [argv[i + 1]] : []));
    assert.deepEqual(disabled, ["shell_tool", "browser_use", "browser_use_external", "computer_use"]);
    // There is no "disable all tools" flag in this argv (contrast claude's `--tools ""`): every other native codex tool
    // is governed by codex's own defaults, which a unit test cannot exercise without running the binary. The SDD's bar
    // is a proof that native shell, file and network tools cannot execute — so the proof record stays null.
    assert.ok(!argv.includes("--tools"));
    assert.equal(CODEX_WRITER_CAPABILITY_PROOF, null);
    const stance = toolStanceFor("codex-headless");
    assert.deepEqual([stance?.adapter, stance?.enforced], ["codex-headless", false]);
    assert.ok(!DEFAULT_WRITER_ROLE_ALLOWLIST.includes("codex-headless"));
    const verdict = checkWriterEligibility(stance, [...DEFAULT_WRITER_ROLE_ALLOWLIST, "codex-headless"]);
    assert.equal(verdict.eligible, false);
    assert.deepEqual(effectiveWriterAllowlist(["codex-headless", "claude-headless"]), ["claude-headless"], "config can narrow the allowlist, never widen it");
  });

  it("an adapter without a stance, an unknown adapter and an unknown adapter version are refused", () => {
    for (const model of ["gemini-headless", "grok-build", "composer-2.5", "no-such-model", "__proto__", "constructor"]) {
      assert.equal(checkWriterEligibility(toolStanceFor(model), DEFAULT_WRITER_ROLE_ALLOWLIST).eligible, false, model);
    }
    assert.equal(checkWriterEligibility(undefined, DEFAULT_WRITER_ROLE_ALLOWLIST).eligible, false);
    const future = { ...toolStanceFor("claude-headless")!, adapter_version: String(Number(TOOL_STANCE_VERSION) + 1) };
    const v = checkWriterEligibility(future, DEFAULT_WRITER_ROLE_ALLOWLIST);
    assert.equal(v.eligible, false);
    if (!v.eligible) assert.match(v.reason, /version/);
  });

  it("an attempted tool call in the dispatch result is refused even for an eligible adapter", () => {
    const v = checkWriterEligibility(toolStanceFor("claude-opus-4-7"), DEFAULT_WRITER_ROLE_ALLOWLIST, { toolCallsAttempted: 1 });
    assert.equal(v.eligible, false);
    if (!v.eligible) assert.match(v.reason, /tool call/);
  });

  it("the allowlist narrows: an adapter outside it is refused", () => {
    assert.equal(checkWriterEligibility(toolStanceFor("gpt-5.5-pro"), effectiveWriterAllowlist(["claude-headless"])).eligible, false);
    assert.deepEqual(effectiveWriterAllowlist(undefined), [...DEFAULT_WRITER_ROLE_ALLOWLIST]);
  });
});

function fakeSpawn(stdout: string) {
  return ((_cmd: string, _args: readonly string[]) => {
    const proc = new EventEmitter() as ChildProcess & EventEmitter;
    const out = new PassThrough();
    const err = new PassThrough();
    proc.stdout = out as unknown as ChildProcess["stdout"];
    proc.stderr = err as unknown as ChildProcess["stderr"];
    (proc as { exitCode: number | null }).exitCode = null;
    setImmediate(() => {
      out.write(stdout);
      out.end();
      err.end();
      (proc as { exitCode: number | null }).exitCode = 0;
      proc.emit("close", 0, null);
    });
    return proc;
  }) as unknown as typeof import("node:child_process").spawn;
}

describe("the adapter self-reports its stance in the dispatch result", () => {
  it("ChevalDelegateAdapter attaches the stance of the dispatched route and counts returned tool calls", async () => {
    const a = new ChevalDelegateAdapter({ model: "claude-headless", chevalScript: "/nonexistent/cheval.py",
      spawnFn: fakeSpawn(JSON.stringify({ content: "ok", model: "claude-opus-4-7", provider: "anthropic", usage: {} })) });
    const r = await a.generateReview({ systemPrompt: "s", userPrompt: "u", maxOutputTokens: 10 });
    assert.deepEqual(r.toolStance, toolStanceFor("claude-headless", "anthropic"));
    assert.equal(r.toolCallsAttempted, undefined);
    const b = new ChevalDelegateAdapter({ model: "anthropic:claude-opus-4-7", chevalScript: "/nonexistent/cheval.py",
      spawnFn: fakeSpawn(JSON.stringify({ content: "", model: "claude-opus-4-7", provider: "anthropic", usage: {},
        tool_calls: [{ id: "toolu_1", type: "function", function: { name: "Bash", arguments: "{}" } }] })) });
    const rb = await b.generateReview({ systemPrompt: "s", userPrompt: "u", maxOutputTokens: 10 });
    assert.equal(rb.toolStance?.adapter, "anthropic-api");
    assert.equal(rb.toolCallsAttempted, 1);
    assert.equal(checkWriterEligibility(rb.toolStance, DEFAULT_WRITER_ROLE_ALLOWLIST, { toolCallsAttempted: rb.toolCallsAttempted }).eligible, false);
  });

  it("a route answered by another provider than the one requested reports no stance (refused)", () => {
    assert.equal(toolStanceFor("gpt-5.5-pro", "anthropic"), undefined);
  });
});

describe("attempted tool calls per eligible adapter are refused by the guard (enrichment_guard_rejected)", () => {
  const consensus = scoreFindings([
    { provider: "anthropic", model: "claude-headless", findings: [{ id: "F-1", title: "t", severity: "MEDIUM", category: "c", file: "a.ts:1", description: "d" }] },
    { provider: "openai", model: "gpt-5.5-pro", findings: [] },
  ], { high_consensus: 700, disputed_delta: 300, low_value: 400, blocker: 700 });
  const grammar: Record<string, string> = {
    "claude-headless": 'Checking.\n<invoke name="Bash">\n<parameter name="command">ls</parameter>\n</invoke>',
    "anthropic-api": '{"type": "tool_use", "id": "toolu_1", "name": "Read", "input": {"path": "/etc/passwd"}}',
    "openai-api": '{"tool_calls": [{"id": "call_1", "type": "function", "function": {"name": "sh", "arguments": "{}"}}]}',
    "google-api": '{"functionCall": {"name": "sh", "args": {}}}',
    "bedrock-api": '{"toolUse": {"toolUseId": "t", "name": "sh", "input": {}}}',
  };
  const models: Record<string, string> = {
    "claude-headless": "claude-headless", "anthropic-api": "claude-opus-4-7", "openai-api": "gpt-5.5-pro",
    "google-api": "gemini-3.1-pro-preview", "bedrock-api": "us.anthropic.claude-haiku-4-5-20251001-v1:0",
  };
  for (const adapter of DEFAULT_WRITER_ROLE_ALLOWLIST) {
    it(`${adapter}: a writer output carrying a tool call is rejected; the un-enriched consensus is posted`, () => {
      const out = composeConsensusReview({
        header: "header", consensus,
        writer: { output: grammar[adapter], stance: toolStanceFor(models[adapter]), allowlist: DEFAULT_WRITER_ROLE_ALLOWLIST, label: adapter },
      });
      assert.deepEqual(out.degradedReasons, ["enrichment_guard_rejected"]);
      assert.ok(!out.body.includes(grammar[adapter]));
      assert.equal((out.body.match(/bridge-findings-start/g) ?? []).length, 1);
    });
  }
});

describe("writer_not_eligible in the pipeline (exit 3, un-enriched consensus posted)", () => {
  it("a codex-headless primary is never dispatched as the writer", async () => {
    const repoRoot = mkdtempSync(join(tmpdir(), "bb-writer-"));
    const dispatched: string[] = [];
    const comments: string[] = [];
    const stub = mock.method(ChevalDelegateAdapter.prototype, "generateReview", async function (this: unknown) {
      const model = String((this as { opts?: { model?: string } }).opts?.model ?? "");
      dispatched.push(model);
      return {
        content: "<!-- bridge-findings-start -->\n```json\n" + JSON.stringify({ schema_version: 1, findings: [
          { id: `${model}-1`, title: "t", severity: "MEDIUM", category: "c", file: "a.ts:1", description: "d" }] }) + "\n```\n<!-- bridge-findings-end -->",
        inputTokens: 1, outputTokens: 1, model, toolStance: toolStanceFor(model),
      };
    });
    try {
      const multiModel = {
        enabled: true,
        models: [
          { provider: "openai", model_id: "codex-headless", role: "primary" },
          { provider: "anthropic", model_id: "claude-headless", role: "reviewer" },
        ],
        api_key_mode: "graceful", consensus: { enabled: true, scoring_thresholds: {} },
      } as MultiModelConfig;
      const config = {
        repos: [], repoRoot, model: "fixture", maxPrs: 1, maxFilesPerPr: 1, maxDiffBytes: 1000,
        maxInputTokens: 1000, maxOutputTokens: 1000, dimensions: [], reviewMarker: "fixture",
        repoOverridePath: "", dryRun: false, excludePatterns: [], sanitizerMode: "default", maxRuntimeMinutes: 1, multiModel,
      } as BridgebuilderConfig;
      const item = { owner: "o", repo: "r", pr: { number: 1, headSha: "h" }, files: [], hash: "x" } as unknown as ReviewItem;
      const result = await executeMultiModelReview(item, "s", "u", config, {
        poster: { postReview: async () => true, hasExistingReview: async () => false, postComment: async ({ body }) => { comments.push(body); return true; } },
        sanitizer: { sanitize: (c) => ({ safe: true, sanitizedContent: c, redactedPatterns: [] }) },
        logger: { info() {}, warn() {}, error() {}, debug() {} },
      }, { template: { buildEnrichmentPrompt: () => ({ systemPrompt: "e", userPrompt: "e" }) } as unknown as PRReviewTemplate, persona: "p" });
      assert.deepEqual(dispatched.sort(), ["claude-headless", "codex-headless"], "two voices, no writer dispatch");
      assert.equal(result.reviewVerdict.degradedReason, "writer_not_eligible");
      assert.equal(result.reviewVerdict.verdict, "COMMENT");
      const consensusBody = comments.at(-1)!;
      assert.match(consensusBody, /writer_not_eligible/);
      assert.equal((consensusBody.match(/bridge-findings-start/g) ?? []).length, 1);
    } finally {
      stub.mock.restore();
      rmSync(repoRoot, { recursive: true, force: true });
    }
  });
});
