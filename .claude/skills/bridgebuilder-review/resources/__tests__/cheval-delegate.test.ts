// cycle-103 Sprint 1 T1.2 — ChevalDelegateAdapter contract tests.
//
// We don't shell out to a real `python3 cheval.py` here. Instead the adapter
// accepts a `spawnFn` test hook; we plug in a fake that scripts stdout/stderr/
// exit-code per scenario. That keeps these tests hermetic and lets us pin the
// SDD §5.3 exit-code → LLMProviderErrorCode translation table exhaustively.

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { PassThrough } from "node:stream";
import type { ChildProcess } from "node:child_process";

import {
  ChevalDelegateAdapter,
  translateExitCode,
} from "../adapters/cheval-delegate.js";
import { LLMProviderError } from "../ports/llm-provider.js";

interface FakeProcessScript {
  stdout?: string;
  stderr?: string;
  exitCode?: number | null;
  signal?: NodeJS.Signals | null;
  /** Override the close delay (ms). Defaults to 0 (next tick). */
  closeAfterMs?: number;
  /** If set, the fake never closes — used to exercise the timeout path. */
  hang?: boolean;
}

interface SpawnCall {
  command: string;
  args: string[];
  env: NodeJS.ProcessEnv | undefined;
}

function makeFakeSpawn(script: FakeProcessScript, calls: SpawnCall[]) {
  return ((command: string, args: readonly string[], opts: { env?: NodeJS.ProcessEnv } = {}) => {
    calls.push({ command, args: [...args], env: opts.env });

    const proc = new EventEmitter() as ChildProcess & EventEmitter & {
      exitCode: number | null;
      signalCode: NodeJS.Signals | null;
      kill: (sig?: NodeJS.Signals) => boolean;
    };
    const stdout = new PassThrough();
    const stderr = new PassThrough();
    proc.stdout = stdout as unknown as ChildProcess["stdout"];
    proc.stderr = stderr as unknown as ChildProcess["stderr"];
    proc.exitCode = null;
    proc.signalCode = null;
    proc.kill = (sig?: NodeJS.Signals) => {
      proc.signalCode = sig ?? "SIGTERM";
      // Emit close shortly after a kill; mirrors real OS behavior.
      setImmediate(() => {
        proc.exitCode = null;
        proc.emit("close", null, sig ?? "SIGTERM");
      });
      return true;
    };

    if (script.hang) {
      // Never close. Caller's timeout path will kill us.
      return proc;
    }

    const fire = () => {
      if (script.stdout) stdout.write(script.stdout);
      if (script.stderr) stderr.write(script.stderr);
      stdout.end();
      stderr.end();
      proc.exitCode = script.exitCode ?? 0;
      proc.emit("close", script.exitCode ?? 0, script.signal ?? null);
    };

    if (script.closeAfterMs && script.closeAfterMs > 0) {
      setTimeout(fire, script.closeAfterMs);
    } else {
      setImmediate(fire);
    }

    return proc;
  }) as unknown as typeof import("node:child_process").spawn;
}

function makeAdapter(script: FakeProcessScript, calls: SpawnCall[], overrides: Partial<Parameters<typeof ChevalDelegateAdapter.prototype.generateReview>[0]> & Record<string, unknown> = {}) {
  return new ChevalDelegateAdapter({
    model: "anthropic:claude-sonnet-4-5-20250929",
    timeoutMs: 5_000,
    chevalScript: "/tmp/fake-cheval.py",
    pythonBin: "/tmp/fake-python3",
    spawnFn: makeFakeSpawn(script, calls),
    ...overrides,
  });
}

const baseRequest = {
  systemPrompt: "You are a code reviewer.",
  userPrompt: "Review this PR diff: ...",
  maxOutputTokens: 4_000,
};

const successStdout = JSON.stringify({
  content: "## Summary\nLooks good.",
  model: "claude-sonnet-4-5-20250929",
  provider: "anthropic",
  usage: { input_tokens: 1500, output_tokens: 200 },
  latency_ms: 8421,
});

describe("ChevalDelegateAdapter — constructor", () => {
  it("requires model", () => {
    assert.throws(
      () =>
        new ChevalDelegateAdapter({ model: "" } as unknown as { model: string }),
      /model.*required/i,
    );
  });

  it("rejects daemon mode in Sprint 1 (T1.3 descoped)", () => {
    assert.throws(
      () =>
        new ChevalDelegateAdapter({
          model: "anthropic:claude-sonnet-4-5",
          mode: "daemon",
        }),
      /daemon-mode/i,
    );
  });

  // Note (cycle-104 sprint-2 T2.14): the prior
  // "LOA_BB_FORCE_LEGACY_FETCH=1 triggers guided rollback error" test
  // was removed alongside the env-var check itself. The legacy fetch
  // path was deleted in cycle-103, so by cycle-104 the hatch only
  // produced a guided-rollback message and carried no actual rollback
  // capability — preserving the test surface would have pinned a dead
  // env-var contract.
});

describe("ChevalDelegateAdapter — request marshaling", () => {
  it("builds correct argv (model, agent, system, input, max-tokens, json output)", async () => {
    const calls: SpawnCall[] = [];
    const adapter = makeAdapter(
      { stdout: successStdout, exitCode: 0 },
      calls,
    );
    await adapter.generateReview(baseRequest);
    assert.equal(calls.length, 1);
    const call = calls[0]!;
    assert.equal(call.command, "/tmp/fake-python3");
    assert.equal(call.args[0], "/tmp/fake-cheval.py");
    assert.ok(call.args.includes("--agent"));
    assert.ok(call.args.includes("--model"));
    const modelIdx = call.args.indexOf("--model");
    assert.equal(call.args[modelIdx + 1], "anthropic:claude-sonnet-4-5-20250929");
    assert.ok(call.args.includes("--system"));
    assert.ok(call.args.includes("--input"));
    const maxIdx = call.args.indexOf("--max-tokens");
    assert.equal(call.args[maxIdx + 1], "4000");
    const fmtIdx = call.args.indexOf("--output-format");
    assert.equal(call.args[fmtIdx + 1], "json");
    assert.ok(call.args.includes("--json-errors"));
  });

  it("AC-1.2 — passes --mock-fixture-dir when set", async () => {
    const calls: SpawnCall[] = [];
    const adapter = makeAdapter(
      { stdout: successStdout, exitCode: 0 },
      calls,
      { mockFixtureDir: "/tmp/fixtures/cycle-1" },
    );
    await adapter.generateReview(baseRequest);
    const flagIdx = calls[0]!.args.indexOf("--mock-fixture-dir");
    assert.notEqual(flagIdx, -1);
    assert.equal(calls[0]!.args[flagIdx + 1], "/tmp/fixtures/cycle-1");
  });

  it("AC-1.2 — omits --mock-fixture-dir when unset", async () => {
    const calls: SpawnCall[] = [];
    const adapter = makeAdapter(
      { stdout: successStdout, exitCode: 0 },
      calls,
    );
    await adapter.generateReview(baseRequest);
    assert.equal(calls[0]!.args.indexOf("--mock-fixture-dir"), -1);
  });

  it("AC-1.8 — api keys NEVER appear in argv", async () => {
    const prior = {
      anthropic: process.env.ANTHROPIC_API_KEY,
      openai: process.env.OPENAI_API_KEY,
      google: process.env.GOOGLE_API_KEY,
    };
    process.env.ANTHROPIC_API_KEY = "sk-ant-test-secret-AAAA";
    process.env.OPENAI_API_KEY = "sk-test-secret-BBBB";
    process.env.GOOGLE_API_KEY = "AIzaSyTestSecretCCCC";
    try {
      const calls: SpawnCall[] = [];
      const adapter = makeAdapter(
        { stdout: successStdout, exitCode: 0 },
        calls,
      );
      await adapter.generateReview(baseRequest);
      const argvText = calls[0]!.args.join(" ");
      assert.ok(!argvText.includes("sk-ant-test-secret-AAAA"));
      assert.ok(!argvText.includes("sk-test-secret-BBBB"));
      assert.ok(!argvText.includes("AIzaSyTestSecretCCCC"));
      // AC-1.8 (a) — env inheritance is the credential path.
      assert.equal(calls[0]!.env?.ANTHROPIC_API_KEY, "sk-ant-test-secret-AAAA");
    } finally {
      if (prior.anthropic === undefined) delete process.env.ANTHROPIC_API_KEY;
      else process.env.ANTHROPIC_API_KEY = prior.anthropic;
      if (prior.openai === undefined) delete process.env.OPENAI_API_KEY;
      else process.env.OPENAI_API_KEY = prior.openai;
      if (prior.google === undefined) delete process.env.GOOGLE_API_KEY;
      else process.env.GOOGLE_API_KEY = prior.google;
    }
  });

  it("rejects empty systemPrompt / userPrompt", async () => {
    const adapter = makeAdapter({ stdout: successStdout, exitCode: 0 }, []);
    await assert.rejects(
      adapter.generateReview({ ...baseRequest, systemPrompt: "" }),
      /systemPrompt.*userPrompt.*required/i,
    );
    await assert.rejects(
      adapter.generateReview({ ...baseRequest, userPrompt: "" }),
      /systemPrompt.*userPrompt.*required/i,
    );
  });

  it("rejects non-positive maxOutputTokens", async () => {
    const adapter = makeAdapter({ stdout: successStdout, exitCode: 0 }, []);
    await assert.rejects(
      adapter.generateReview({ ...baseRequest, maxOutputTokens: 0 }),
      /maxOutputTokens/i,
    );
    await assert.rejects(
      adapter.generateReview({ ...baseRequest, maxOutputTokens: Number.NaN }),
      /maxOutputTokens/i,
    );
  });
});

describe("ChevalDelegateAdapter — success path", () => {
  it("parses cheval json output and returns ReviewResponse", async () => {
    const adapter = makeAdapter(
      { stdout: successStdout, exitCode: 0 },
      [],
    );
    const result = await adapter.generateReview(baseRequest);
    assert.equal(result.content, "## Summary\nLooks good.");
    assert.equal(result.inputTokens, 1500);
    assert.equal(result.outputTokens, 200);
    assert.equal(result.model, "claude-sonnet-4-5-20250929");
    assert.equal(result.provider, "anthropic");
    assert.equal(result.latencyMs, 8421);
  });

  it("falls back to constructor model when cheval omits it", async () => {
    const stdout = JSON.stringify({
      content: "x",
      usage: { input_tokens: 1, output_tokens: 1 },
    });
    const adapter = makeAdapter(
      { stdout, exitCode: 0 },
      [],
    );
    const result = await adapter.generateReview(baseRequest);
    assert.equal(result.model, "anthropic:claude-sonnet-4-5-20250929");
  });
});

describe("ChevalDelegateAdapter — error translation (SDD §5.3 table)", () => {
  it("exit 1 + RATE_LIMITED → RATE_LIMITED", async () => {
    const adapter = makeAdapter(
      {
        stderr: JSON.stringify({ code: "RATE_LIMITED", message: "429 Too Many Requests" }),
        exitCode: 1,
      },
      [],
    );
    await assert.rejects(
      adapter.generateReview(baseRequest),
      (err: unknown) =>
        err instanceof LLMProviderError && err.code === "RATE_LIMITED",
    );
  });

  it("exit 1 + ProviderUnavailable → PROVIDER_ERROR", async () => {
    const adapter = makeAdapter(
      {
        stderr: JSON.stringify({ code: "PROVIDER_UNAVAILABLE", message: "503" }),
        exitCode: 1,
      },
      [],
    );
    await assert.rejects(
      adapter.generateReview(baseRequest),
      (err: unknown) =>
        err instanceof LLMProviderError && err.code === "PROVIDER_ERROR",
    );
  });

  it("exit 2 → INVALID_REQUEST", async () => {
    const adapter = makeAdapter({ stderr: '{"code":"INVALID_INPUT","message":"x"}', exitCode: 2 }, []);
    await assert.rejects(
      adapter.generateReview(baseRequest),
      (err: unknown) =>
        err instanceof LLMProviderError && err.code === "INVALID_REQUEST",
    );
  });

  it("exit 3 → TIMEOUT", async () => {
    const adapter = makeAdapter({ stderr: '{"code":"TIMEOUT","message":"x"}', exitCode: 3 }, []);
    await assert.rejects(
      adapter.generateReview(baseRequest),
      (err: unknown) =>
        err instanceof LLMProviderError && err.code === "TIMEOUT",
    );
  });

  it("exit 4 → AUTH_ERROR", async () => {
    const adapter = makeAdapter(
      { stderr: '{"code":"MISSING_API_KEY","message":"set ANTHROPIC_API_KEY"}', exitCode: 4 },
      [],
    );
    await assert.rejects(
      adapter.generateReview(baseRequest),
      (err: unknown) =>
        err instanceof LLMProviderError && err.code === "AUTH_ERROR",
    );
  });

  it("exit 5 → PROVIDER_ERROR", async () => {
    const adapter = makeAdapter({ stderr: '{"code":"INVALID_RESPONSE","message":"x"}', exitCode: 5 }, []);
    await assert.rejects(
      adapter.generateReview(baseRequest),
      (err: unknown) =>
        err instanceof LLMProviderError && err.code === "PROVIDER_ERROR",
    );
  });

  it("exit 6 (budget exceeded) → INVALID_REQUEST", async () => {
    const adapter = makeAdapter({ stderr: '{"code":"BUDGET_EXCEEDED","message":"x"}', exitCode: 6 }, []);
    await assert.rejects(
      adapter.generateReview(baseRequest),
      (err: unknown) =>
        err instanceof LLMProviderError && err.code === "INVALID_REQUEST",
    );
  });

  it("exit 7 (context too large) → TOKEN_LIMIT", async () => {
    const adapter = makeAdapter({ stderr: '{"code":"CONTEXT_TOO_LARGE","message":"x"}', exitCode: 7 }, []);
    await assert.rejects(
      adapter.generateReview(baseRequest),
      (err: unknown) =>
        err instanceof LLMProviderError && err.code === "TOKEN_LIMIT",
    );
  });

  it("unknown exit code → PROVIDER_ERROR", async () => {
    const adapter = makeAdapter({ stderr: "diagnostic", exitCode: 42 }, []);
    await assert.rejects(
      adapter.generateReview(baseRequest),
      (err: unknown) =>
        err instanceof LLMProviderError && err.code === "PROVIDER_ERROR",
    );
  });

  it("AC-1.9 (c) — empty stdout on exit 0 → PROVIDER_ERROR (MalformedDelegateError)", async () => {
    const adapter = makeAdapter({ stdout: "", exitCode: 0 }, []);
    await assert.rejects(
      adapter.generateReview(baseRequest),
      (err: unknown) =>
        err instanceof LLMProviderError &&
        err.code === "PROVIDER_ERROR" &&
        /MalformedDelegateError/.test(err.message),
    );
  });

  it("AC-1.9 (c) — partial JSON on exit 0 → PROVIDER_ERROR (MalformedDelegateError)", async () => {
    const adapter = makeAdapter(
      { stdout: '{"content": "incomplete', exitCode: 0 },
      [],
    );
    await assert.rejects(
      adapter.generateReview(baseRequest),
      (err: unknown) =>
        err instanceof LLMProviderError &&
        err.code === "PROVIDER_ERROR" &&
        /MalformedDelegateError/.test(err.message),
    );
  });

  it("AC-1.9 (c) — exit 0 JSON without content field → PROVIDER_ERROR", async () => {
    const adapter = makeAdapter(
      { stdout: JSON.stringify({ model: "x", usage: {} }), exitCode: 0 },
      [],
    );
    await assert.rejects(
      adapter.generateReview(baseRequest),
      (err: unknown) =>
        err instanceof LLMProviderError &&
        err.code === "PROVIDER_ERROR" &&
        /MalformedDelegateError/.test(err.message),
    );
  });
});

describe("ChevalDelegateAdapter — AC-1.9 (b) timeout / lifecycle", () => {
  it("hangs past timeoutMs → kills child with SIGTERM and throws TIMEOUT", async () => {
    const calls: SpawnCall[] = [];
    const adapter = new ChevalDelegateAdapter({
      model: "anthropic:claude-sonnet-4-5",
      timeoutMs: 50,
      chevalScript: "/tmp/fake-cheval.py",
      pythonBin: "/tmp/fake-python3",
      spawnFn: makeFakeSpawn({ hang: true }, calls),
    });
    await assert.rejects(
      adapter.generateReview(baseRequest),
      (err: unknown) =>
        err instanceof LLMProviderError && err.code === "TIMEOUT",
    );
  });
});

describe("translateExitCode — table-pinned", () => {
  // Direct call coverage so the table is grep-able from a code review.
  const cases: Array<[number | null, string, string]> = [
    [1, '{"code":"RATE_LIMITED","message":"x"}', "RATE_LIMITED"],
    [1, '{"code":"PROVIDER_UNAVAILABLE","message":"x"}', "PROVIDER_ERROR"],
    [1, "", "PROVIDER_ERROR"],
    [2, "", "INVALID_REQUEST"],
    [3, "", "TIMEOUT"],
    [4, "", "AUTH_ERROR"],
    [5, "", "PROVIDER_ERROR"],
    [6, "", "INVALID_REQUEST"],
    [7, "", "TOKEN_LIMIT"],
    [null, "", "NETWORK"],
    [99, "", "PROVIDER_ERROR"],
  ];
  for (const [exit, stderr, expected] of cases) {
    it(`exit=${exit} → ${expected}`, () => {
      const err = translateExitCode(exit, stderr);
      assert.equal(err.code, expected);
    });
  }
});
