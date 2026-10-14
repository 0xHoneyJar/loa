// cycle-129 Sprint 3 Task 3.4 / 3.5 (SDD D-7.5, D-8.1; DEC-0170): Bridgebuilder reads hounfour.providers, the locality
// switch and bridgebuilder.exit_on_degraded ONLY from trusted configuration — the base branch's config or repository
// settings on a pull request, the working tree locally. A keyless or insecure provider only the PR head declares is refused
// by name; an undeclared provider is still "Unknown provider".
import { describe, it, mock } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  applyLocality,
  computeHeadDrift,
  defaultTrustedConfigDeps,
  EXIT_TRUSTED_CONFIG_DRIFT,
  headDriftRefusal,
  jsonDeepEqual,
  LOCAL_FALLBACK_MAX_DEPTH,
  localVoiceDecision,
  resolveFallbackSpec,
  headOnlyRefusal,
  isLocalVoice,
  isPullRequestContext,
  isSafeRefName,
  loadTrustedConfig,
  localEndpointHost,
  localityRefusal,
  providerKeyEnv,
  singleModelLocalityRefusal,
  validateApiKeys,
  yqTrustedView,
  type AgyGate,
  type TrustedConfigDeps,
} from "../config.js";
import { ChevalDelegateAdapter } from "../adapters/cheval-delegate.js";
import { executeMultiModelReview } from "../core/multi-model-pipeline.js";
import type { BridgebuilderConfig, MultiModelConfig, ReviewItem, TrustedConfig } from "../core/types.js";
import type { PRReviewTemplate } from "../core/template.js";

const GATE: AgyGate = { optIn: false, mode: "prefer-api" };

const LOCAL_PROVIDER_YAML = [
  "hounfour:",
  "  providers:",
  "    local-vllm:",
  "      type: openai_compat",
  "      endpoint: \"http://127.0.0.1:8000/v1\"",
  "      keyless: true",
  "      allow_insecure_endpoint: \"127.0.0.1\"",
  "      models:",
  "        qwen3-coder:",
  "          dispatch_group: local",
  "          context_window: 32768",
  "",
].join("\n");

const EMPTY_YAML = "hounfour:\n  providers: {}\n";

function mm(models: Array<{ provider: string; model_id: string }>): MultiModelConfig {
  return {
    enabled: true,
    models: models.map((m) => ({ ...m, role: "reviewer" as const })),
    api_key_mode: "graceful",
  } as MultiModelConfig;
}

/** Fake I/O: a working tree (the head, on a PR) and a map of ref -> base config text. */
function fakeDeps(opts: {
  env?: Record<string, string | undefined>;
  head?: string;
  refs?: Record<string, string | undefined>;
  prBase?: string;
}): TrustedConfigDeps & { shown: string[] } {
  const shown: string[] = [];
  return {
    shown,
    env: opts.env ?? {},
    readWorkingTree: () => opts.head,
    refExists: (_root, ref) => Object.hasOwn(opts.refs ?? {}, ref),
    gitShow: (_root, ref) => {
      shown.push(ref);
      return (opts.refs ?? {})[ref];
    },
    prBaseRef: () => opts.prBase,
    parse: yqTrustedView,
  };
}

describe("trusted provider configuration (D-7.5)", () => {
  it("local mode trusts the working tree: a keyless provider needs no env var", () => {
    const deps = fakeDeps({ head: LOCAL_PROVIDER_YAML });
    const t = loadTrustedConfig({}, deps);
    assert.equal(t.mode, "local");
    assert.equal(t.source, "working-tree");
    assert.equal(t.providers["local-vllm"]?.keyless, true);
    assert.deepEqual(t.headOnlyRefused, []);
    assert.deepEqual(deps.shown, [], "no git read in local mode");
    const ks = validateApiKeys(mm([{ provider: "local-vllm", model_id: "qwen3-coder" }]), GATE, t);
    assert.deepEqual(ks.valid, [{ provider: "local-vllm", modelId: "qwen3-coder" }]);
    assert.deepEqual(ks.missing, []);
  });

  it("on a pull request a keyless provider from the base branch's config is accepted", () => {
    const deps = fakeDeps({
      env: { GITHUB_EVENT_NAME: "pull_request", GITHUB_BASE_REF: "main" },
      head: LOCAL_PROVIDER_YAML,
      refs: { "refs/remotes/origin/main": LOCAL_PROVIDER_YAML },
    });
    const t = loadTrustedConfig({ pr: 7 }, deps);
    assert.equal(t.mode, "pull-request");
    assert.equal(t.source, "base-ref");
    assert.equal(t.ref, "refs/remotes/origin/main");
    assert.deepEqual(t.headOnlyRefused, []);
    const ks = validateApiKeys(mm([{ provider: "local-vllm", model_id: "qwen3-coder" }]), GATE, t);
    assert.deepEqual(ks.valid.map((v) => v.provider), ["local-vllm"]);
  });

  it("a keyless provider declared only in the PR head is refused by name", () => {
    const deps = fakeDeps({
      env: { GITHUB_BASE_REF: "main" },
      head: LOCAL_PROVIDER_YAML,
      refs: { "refs/remotes/origin/main": EMPTY_YAML },
    });
    const t = loadTrustedConfig({ pr: 7 }, deps);
    assert.deepEqual(t.headOnlyRefused, ["local-vllm"]);
    assert.ok(t.warnings.some((w) => w.includes("head-only provider declaration refused: local-vllm")), t.warnings.join("\n"));
    assert.equal(t.providers["local-vllm"], undefined, "the head's declaration never enters the trusted view");
    const ks = validateApiKeys(mm([{ provider: "local-vllm", model_id: "qwen3-coder" }]), GATE, t);
    assert.deepEqual(ks.valid, []);
    assert.deepEqual(ks.missing, [{ provider: "local-vllm", envVar: headOnlyRefusal("local-vllm") }]);
    assert.equal(headOnlyRefusal("local-vllm"), "head-only provider declaration refused: local-vllm");
  });

  it("a head that re-declares a built-in provider with an insecure endpoint is refused by name", () => {
    const head = "hounfour:\n  providers:\n    openai:\n      endpoint: \"http://10.0.0.5/v1\"\n      allow_insecure_endpoint: \"10.0.0.5\"\n";
    const deps = fakeDeps({ env: { GITHUB_BASE_REF: "main" }, head, refs: { "refs/remotes/origin/main": EMPTY_YAML } });
    const prev = process.env.OPENAI_API_KEY;
    process.env.OPENAI_API_KEY = "sk-fixture";
    try {
      const t = loadTrustedConfig({ pr: 3 }, deps);
      assert.deepEqual(t.headOnlyRefused, ["openai"]);
      const ks = validateApiKeys(mm([{ provider: "openai", model_id: "gpt-5.5" }]), GATE, t);
      assert.deepEqual(ks.missing, [{ provider: "openai", envVar: "head-only provider declaration refused: openai" }]);
    } finally {
      if (prev === undefined) delete process.env.OPENAI_API_KEY;
      else process.env.OPENAI_API_KEY = prev;
    }
  });

  it("a provider absent from the trusted config still fails with Unknown provider", () => {
    for (const t of [
      loadTrustedConfig({}, fakeDeps({ head: LOCAL_PROVIDER_YAML })),
      loadTrustedConfig({ pr: 1 }, fakeDeps({ env: { GITHUB_BASE_REF: "main" }, head: EMPTY_YAML, refs: { "refs/remotes/origin/main": LOCAL_PROVIDER_YAML } })),
    ]) {
      const ks = validateApiKeys(mm([{ provider: "mystery", model_id: "m1" }]), GATE, t);
      assert.deepEqual(ks.missing, [{ provider: "mystery", envVar: "Unknown provider: mystery" }]);
      assert.deepEqual(ks.valid, []);
    }
    // and with no trusted view at all (the pre-cycle-129 call shape)
    const ks = validateApiKeys(mm([{ provider: "mystery", model_id: "m1" }]), GATE);
    assert.deepEqual(ks.missing, [{ provider: "mystery", envVar: "Unknown provider: mystery" }]);
  });

  it("repository settings (BRIDGEBUILDER_TRUSTED_CONFIG) win over the base branch on a pull request", () => {
    const deps = fakeDeps({
      env: { GITHUB_BASE_REF: "main", BRIDGEBUILDER_TRUSTED_CONFIG: JSON.stringify({ hounfour: { providers: { "local-vllm": { keyless: true } } } }) },
      head: LOCAL_PROVIDER_YAML,
      refs: { "refs/remotes/origin/main": EMPTY_YAML },
    });
    const t = loadTrustedConfig({ pr: 9 }, deps);
    assert.equal(t.source, "repository-settings");
    assert.deepEqual(deps.shown, [], "the base ref is not read when settings answer");
    assert.equal(t.providers["local-vllm"]?.keyless, true);
    // (the head adds allow_insecure_endpoint, which the settings do not grant: refused)
    assert.deepEqual(t.headOnlyRefused, ["local-vllm"]);
  });

  it("falls back to origin/main when the PR base ref is not present, and to none when nothing answers", () => {
    const deps = fakeDeps({
      env: { GITHUB_BASE_REF: "develop" },
      head: LOCAL_PROVIDER_YAML,
      refs: { "refs/remotes/origin/main": LOCAL_PROVIDER_YAML },
    });
    const t = loadTrustedConfig({ pr: 2 }, deps);
    assert.equal(t.ref, "refs/remotes/origin/main");
    assert.deepEqual(t.headOnlyRefused, []);

    const none = loadTrustedConfig({ pr: 2 }, fakeDeps({ env: { GITHUB_BASE_REF: "develop" }, head: LOCAL_PROVIDER_YAML, refs: {} }));
    assert.equal(none.source, "none");
    assert.deepEqual(none.providers, {});
    assert.deepEqual(none.headOnlyRefused, ["local-vllm"], "no trusted source: the head's keyless provider is refused");
    assert.ok(none.warnings.some((w) => w.includes("trusted config unavailable on a pull request")));
  });

  it("reads the base branch from the PR metadata when GITHUB_BASE_REF is unset", () => {
    const deps = fakeDeps({
      head: LOCAL_PROVIDER_YAML,
      refs: { "refs/remotes/origin/release/2.0": LOCAL_PROVIDER_YAML, "refs/remotes/origin/main": EMPTY_YAML },
      prBase: "release/2.0",
    });
    const t = loadTrustedConfig({ pr: 44 }, deps);
    assert.equal(t.ref, "refs/remotes/origin/release/2.0");
    assert.deepEqual(t.headOnlyRefused, []);
  });

  it("refuses an unsafe base ref name and never passes it to git", () => {
    for (const bad of ["--output=/tmp/x", "a..b", "-x", "main.lock", "x y"]) assert.equal(isSafeRefName(bad), false, bad);
    assert.equal(isSafeRefName("feature/cycle-129"), true);
    const deps = fakeDeps({ env: { GITHUB_BASE_REF: "--upload-pack=evil" }, head: EMPTY_YAML, refs: { "refs/remotes/origin/main": EMPTY_YAML } });
    const t = loadTrustedConfig({ pr: 1 }, deps);
    assert.deepEqual(deps.shown, ["refs/remotes/origin/main"]);
    assert.ok(t.warnings.some((w) => w.includes("base ref name refused")));
  });

  it("a literal auth is keyless (D-8.0); an {env:VAR} auth names the key env var", () => {
    const yaml = [
      "hounfour:",
      "  providers:",
      "    lit:",
      "      auth: \"local\"",
      "    tmpl:",
      "      auth: \"{env:TMPL_KEY}\"",
      "",
    ].join("\n");
    const t = loadTrustedConfig({}, fakeDeps({ head: yaml }));
    assert.equal(t.providers.lit?.keyless, true);
    assert.equal(t.providers.tmpl?.keyless, false);
    assert.equal(providerKeyEnv("tmpl", t), "TMPL_KEY");
    assert.equal(providerKeyEnv("openai", t), "OPENAI_API_KEY");
    const prev = process.env.TMPL_KEY;
    delete process.env.TMPL_KEY;
    try {
      let ks = validateApiKeys(mm([{ provider: "tmpl", model_id: "x" }]), GATE, t);
      assert.deepEqual(ks.missing, [{ provider: "tmpl", envVar: "TMPL_KEY" }]);
      process.env.TMPL_KEY = "fixture";
      ks = validateApiKeys(mm([{ provider: "tmpl", model_id: "x" }]), GATE, t);
      assert.deepEqual(ks.valid.map((v) => v.provider), ["tmpl"]);
    } finally {
      if (prev === undefined) delete process.env.TMPL_KEY;
      else process.env.TMPL_KEY = prev;
    }
  });

  it("bridgebuilder.exit_on_degraded: default 3, 0 honoured, an invalid value warns and uses 3", () => {
    assert.equal(loadTrustedConfig({}, fakeDeps({ head: EMPTY_YAML })).exitOnDegraded, 3);
    assert.equal(loadTrustedConfig({}, fakeDeps({ head: "bridgebuilder:\n  exit_on_degraded: 0\n" })).exitOnDegraded, 0);
    const bad = loadTrustedConfig({}, fakeDeps({ head: "bridgebuilder:\n  exit_on_degraded: \"zero\"\n" }));
    assert.equal(bad.exitOnDegraded, 3);
    assert.ok(bad.warnings.some((w) => w.includes("exit_on_degraded: invalid value")));
    // (on a PR the head cannot lower it: the base's value wins)
    const pr = loadTrustedConfig({ pr: 5 }, fakeDeps({
      env: { GITHUB_BASE_REF: "main" },
      head: "bridgebuilder:\n  exit_on_degraded: 0\n",
      refs: { "refs/remotes/origin/main": EMPTY_YAML },
    }));
    assert.equal(pr.exitOnDegraded, 3);
  });

  it("detects the pull-request context from --pr, the event name or the base ref", () => {
    assert.equal(isPullRequestContext(undefined, {}), false);
    assert.equal(isPullRequestContext(12, {}), true);
    assert.equal(isPullRequestContext(undefined, { GITHUB_EVENT_NAME: "pull_request_target" }), true);
    assert.equal(isPullRequestContext(undefined, { GITHUB_EVENT_NAME: "push" }), false);
    assert.equal(isPullRequestContext(undefined, { GITHUB_BASE_REF: "main" }), true);
  });

  it("the default git seam reads .loa.config.yaml at refs/remotes/origin/<base>, not the working tree", () => {
    const repo = mkdtempSync(join(tmpdir(), "bb-trusted-git-"));
    const git = (...args: string[]) => execFileSync("git", ["-C", repo, ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
    try {
      git("init", "-q");
      git("config", "user.email", "fixture@example.invalid");
      git("config", "user.name", "fixture");
      git("config", "commit.gpgsign", "false");
      writeFileSync(join(repo, ".loa.config.yaml"), LOCAL_PROVIDER_YAML);
      git("add", ".loa.config.yaml");
      git("commit", "-q", "-m", "base");
      git("update-ref", "refs/remotes/origin/main", "HEAD");
      // the PR head: drops keyless from the base declaration and adds a head-only provider
      writeFileSync(join(repo, ".loa.config.yaml"), LOCAL_PROVIDER_YAML + "    evil:\n      keyless: true\n");
      const t = loadTrustedConfig({ pr: 1, repoRoot: repo }, { ...defaultTrustedConfigDeps, env: { GITHUB_BASE_REF: "main" } });
      assert.equal(t.source, "base-ref");
      assert.equal(t.providers["local-vllm"]?.keyless, true);
      assert.equal(t.providers.evil, undefined);
      assert.deepEqual(t.headOnlyRefused, ["evil"]);
      // a base without the file is an empty trusted config, not a failure
      git("rm", "-q", "-f", ".loa.config.yaml");
      git("commit", "-q", "-m", "drop config");
      git("update-ref", "refs/remotes/origin/main", "HEAD");
      writeFileSync(join(repo, ".loa.config.yaml"), LOCAL_PROVIDER_YAML);
      const t2 = loadTrustedConfig({ pr: 1, repoRoot: repo }, { ...defaultTrustedConfigDeps, env: { GITHUB_BASE_REF: "main" } });
      assert.equal(t2.source, "base-ref");
      assert.deepEqual(t2.providers, {});
      assert.deepEqual(t2.headOnlyRefused, ["local-vllm"]);
    } finally {
      rmSync(repo, { recursive: true, force: true });
    }
  });
});

describe("hounfour.locality: local_voices in Bridgebuilder (D-8.1)", () => {
  const yaml = [
    "hounfour:",
    "  locality: local_voices",
    "  providers:",
    "    local-vllm:",
    "      endpoint: \"http://127.0.0.1:8000/v1\"",
    "      keyless: true",
    "      models:",
    "        qwen3-coder:",
    "          dispatch_group: local",
    "    lan-box:",
    "      endpoint: \"https://192.168.1.10:8443/v1\"",
    "      keyless: true",
    "      dispatch_group: local",
    "    openai:",
    "      models:",
    "        gpt-5.5:",
    "          dispatch_group: openai-gpt",
    "",
  ].join("\n");

  it("drops every hosted voice with the named reason and keeps the local ones; never reroutes", () => {
    const t = loadTrustedConfig({}, fakeDeps({ head: yaml }));
    assert.equal(t.locality, "local_voices");
    const models = mm([
      { provider: "local-vllm", model_id: "qwen3-coder" },
      { provider: "openai", model_id: "gpt-5.5" },
      { provider: "anthropic", model_id: "claude-opus-5-5" },
      { provider: "lan-box", model_id: "anything" },
    ]).models;
    const r = applyLocality(models, t);
    assert.deepEqual(r.kept.map((m) => `${m.provider}/${m.model_id}`), ["local-vllm/qwen3-coder", "lan-box/anything"]);
    assert.deepEqual(r.refused.map((x) => x.reason), [
      "locality: local_voices refuses hosted hop gpt-5.5 (openai); declare a local provider or set hounfour.locality: hosted",
      "locality: local_voices refuses hosted hop claude-opus-5-5 (anthropic); declare a local provider or set hounfour.locality: hosted",
    ]);
    assert.equal(r.refused[0].reason, localityRefusal("gpt-5.5", "openai"));
  });

  it("hosted (the default) leaves the plan unchanged", () => {
    const t = loadTrustedConfig({}, fakeDeps({ head: yaml.replace("  locality: local_voices\n", "") }));
    assert.equal(t.locality, "hosted");
    const models = mm([{ provider: "openai", model_id: "gpt-5.5" }, { provider: "local-vllm", model_id: "qwen3-coder" }]).models;
    const r = applyLocality(models, t);
    assert.equal(r.kept, models);
    assert.deepEqual(r.refused, []);
  });

  it("the locality switch is read from the trusted source: a PR head cannot turn local_voices off", () => {
    const t = loadTrustedConfig({ pr: 4 }, fakeDeps({
      env: { GITHUB_BASE_REF: "main" },
      head: yaml.replace("locality: local_voices", "locality: hosted"),
      refs: { "refs/remotes/origin/main": yaml },
    }));
    assert.equal(t.locality, "local_voices");
  });

  it("an invalid locality value refuses to start rather than running hosted", () => {
    assert.throws(
      () => loadTrustedConfig({}, fakeDeps({ head: "hounfour:\n  locality: local-voices\n" })),
      /hounfour\.locality: invalid value "local-voices"/,
    );
  });

  it("a provider with no dispatch_group is hosted; the single-model voice obeys the switch", () => {
    const t = loadTrustedConfig({}, fakeDeps({ head: yaml }));
    assert.equal(isLocalVoice("local-vllm", "qwen3-coder", t), true);
    assert.equal(isLocalVoice("local-vllm", "unlisted-alias", t), true, "every declared model is local");
    assert.equal(isLocalVoice("openai", "gpt-5.5", t), false);
    assert.equal(isLocalVoice("nobody", "x", t), false);
    assert.equal(singleModelLocalityRefusal("local-vllm:qwen3-coder", t), undefined);
    assert.match(singleModelLocalityRefusal("opus", t) ?? "", /^locality: local_voices refuses hosted hop opus \(/);
    const hosted: TrustedConfig = { ...t, locality: "hosted" };
    assert.equal(singleModelLocalityRefusal("opus", hosted), undefined);
  });

  it("a dispatch_group local voice whose endpoint host is not local (or a CLI provider) is hosted and dropped by name (r257-1)", () => {
    const mislabelled = yaml + [
      "    hostedbox:",
      "      endpoint: \"https://api.acme.example/v1\"",
      "      models:",
      "        qwen-hosted:",
      "          dispatch_group: local",
      "    metabox:",
      "      endpoint: \"https://169.254.169.254/v1\"",
      "      dispatch_group: local",
      "    noend:",
      "      models:",
      "        n1:",
      "          dispatch_group: local",
      "    clibox:",
      "      type: claude-headless",
      "      models:",
      "        c1:",
      "          dispatch_group: local",
      "",
    ].join("\n");
    const t = loadTrustedConfig({}, fakeDeps({ head: mislabelled }));
    assert.equal(t.providers.hostedbox.endpoint, "https://api.acme.example/v1", "the trusted reader carries the endpoint");
    const models = mm([
      { provider: "hostedbox", model_id: "qwen-hosted" },
      { provider: "metabox", model_id: "m" },
      { provider: "noend", model_id: "n1" },
      { provider: "clibox", model_id: "c1" },
      { provider: "local-vllm", model_id: "qwen3-coder" },
    ]).models;
    const r = applyLocality(models, t);
    assert.deepEqual(r.kept.map((m) => `${m.provider}/${m.model_id}`), ["local-vllm/qwen3-coder"]);
    assert.deepEqual(r.refused.map((x) => x.reason), [
      "locality: local_voices refuses hosted hop qwen-hosted (hostedbox): dispatch_group local but endpoint host api.acme.example is not a loopback or RFC1918 IP literal or localhost",
      "locality: local_voices refuses hosted hop m (metabox): dispatch_group local but endpoint host 169.254.169.254 is not a loopback or RFC1918 IP literal or localhost",
      "locality: local_voices refuses hosted hop n1 (noend): dispatch_group local but endpoint host (none declared) is not a loopback or RFC1918 IP literal or localhost",
      "locality: local_voices refuses hosted hop c1 (clibox): dispatch_group local but clibox is a CLI provider",
    ]);
    assert.match(singleModelLocalityRefusal("hostedbox:qwen-hosted", t) ?? "", /endpoint host api\.acme\.example is not a loopback/);
  });

  it("the local-hop host rule matches the cheval validator's ranges (localEndpointHost)", () => {
    const local = [
      "http://127.0.0.1:8000/v1", "https://127.9.9.9/v1", "http://[::1]:8000/v1", "https://[0:0:0:0:0:0:0:1]/v1",
      "http://localhost:11434/v1", "http://LOCALHOST./v1", "https://10.0.0.5/v1", "https://172.16.0.1/v1",
      "https://172.31.255.255/v1", "https://192.168.1.10:8443/v1",
    ];
    for (const e of local) assert.equal(localEndpointHost(e).ok, true, e);
    const hosted = [
      "https://api.acme.example/v1", "https://169.254.169.254/v1", "https://169.254.1.1/v1", "http://[fe80::1]/v1",
      "http://[fd12::1]/v1", "https://203.0.113.5/v1", "https://8.8.8.8/v1", "https://172.32.0.1/v1",
      "https://0x7f.1/v1", "https://127.000.0.1/v1", "http://[::ffff:127.0.0.1]/v1", "ftp://127.0.0.1/v1",
      "https://localhost.example/v1", "not a url", "", "http://127.0.0.1:99999/v1",
    ];
    for (const e of hosted) assert.equal(localEndpointHost(e).ok, false, e);
    assert.equal(localEndpointHost(undefined).host, "");
    assert.equal(localEndpointHost("https://[0:0:0:0:0:0:0:1]:8443/v1").host, "::1");
  });
});

describe("the pipeline dispatches a trusted keyless voice with no key (D-7.5)", () => {
  it("a keyless provider from the trusted config reaches cheval; a head-only one does not", async () => {
    const repoRoot = mkdtempSync(join(tmpdir(), "bb-keyless-"));
    const seen: string[] = [];
    const stub = mock.method(ChevalDelegateAdapter.prototype, "generateReview", async function (this: unknown) {
      seen.push(String((this as { opts?: { model?: string } }).opts?.model ?? ""));
      return {
        content: "<!-- bridge-findings-start -->\n```json\n" + JSON.stringify({ schema_version: 1, findings: [] }) + "\n```\n<!-- bridge-findings-end -->",
        inputTokens: 1, outputTokens: 1, model: "fixture",
      };
    });
    try {
      const trusted = loadTrustedConfig({ pr: 22 }, fakeDeps({
        env: { GITHUB_BASE_REF: "main" },
        head: LOCAL_PROVIDER_YAML + "    evil:\n      keyless: true\n",
        refs: { "refs/remotes/origin/main": LOCAL_PROVIDER_YAML },
      }));
      const multiModel = {
        ...mm([{ provider: "local-vllm", model_id: "qwen3-coder" }, { provider: "evil", model_id: "x" }]),
        consensus: { enabled: true, scoring_thresholds: {} },
      } as MultiModelConfig;
      const config = {
        repos: [], repoRoot, model: "fixture", maxPrs: 1, maxFilesPerPr: 1, maxDiffBytes: 1000,
        maxInputTokens: 1000, maxOutputTokens: 1000, dimensions: [], reviewMarker: "fixture",
        repoOverridePath: "", dryRun: true, excludePatterns: [], sanitizerMode: "default",
        maxRuntimeMinutes: 1, multiModel, trusted,
      } as unknown as BridgebuilderConfig;
      const item = { owner: "fixture", repo: "repo", pr: { number: 22, headSha: "fixture" }, files: [], hash: "fixture" } as unknown as ReviewItem;
      const result = await executeMultiModelReview(item, "fixture", "fixture", config, {
        poster: { postReview: async () => true, hasExistingReview: async () => false, postComment: async () => true },
        sanitizer: { sanitize: (content) => ({ safe: true, sanitizedContent: content, redactedPatterns: [] }) },
        logger: { info() {}, warn() {}, error() {}, debug() {} },
      });
      assert.ok(seen.includes("qwen3-coder"), `dispatched ${JSON.stringify(seen)}`);
      assert.ok(!seen.includes("x"), "the head-only provider is never dispatched");
      assert.deepEqual(result.voicesPlanned, ["local-vllm/qwen3-coder", "evil/x"]);
      assert.equal(result.reviewVerdict.mergeBlocked, true, "a refused planned voice never clears a merge");
    } finally {
      stub.mock.restore();
      rmSync(repoRoot, { recursive: true, force: true });
    }
  });
});

// audit a257-1 MEDIUM-A1 (c): under local_voices a local voice whose own fallback_chain reaches a hosted hop is hosted —
// cheval walks that chain inside one call. The trusted reader carries per-model fallback_chain and the trusted aliases.
describe("a local voice's fallback_chain under local_voices (audit a257-1 MEDIUM-A1 (c))", () => {
  const yaml = [
    "hounfour:",
    "  locality: local_voices",
    "  aliases:",
    "    lb: \"local-vllm:qwen-b\"",
    "    hosted-alias: \"openai:gpt-5.5\"",
    "    loop-a: \"loop-b\"",
    "    loop-b: \"loop-a\"",
    "  providers:",
    "    local-vllm:",
    "      endpoint: \"http://127.0.0.1:8000/v1\"",
    "      keyless: true",
    "      models:",
    "        qwen-a:",
    "          dispatch_group: local",
    "          fallback_chain: [\"local-vllm:qwen-b\", \"lb\"]",
    "        qwen-b:",
    "          dispatch_group: local",
    "          fallback_chain: [\"local-vllm:qwen-a\"]",
    "        qwen-pin:",
    "          dispatch_group: local",
    "          fallback_chain: [\"openai:gpt-5.5\"]",
    "        qwen-alias:",
    "          dispatch_group: local",
    "          fallback_chain: [\"hosted-alias\"]",
    "        qwen-unresolved:",
    "          dispatch_group: local",
    "          fallback_chain: [\"loop-a\"]",
    "        qwen-deep:",
    "          dispatch_group: local",
    "          fallback_chain: [\"local-vllm:qwen-pin\"]",
    "    openai:",
    "      models:",
    "        gpt-5.5:",
    "          dispatch_group: openai-gpt",
    "",
  ].join("\n");

  it("the trusted reader carries fallback_chain per model and the trusted aliases", () => {
    const t = loadTrustedConfig({}, fakeDeps({ head: yaml }));
    assert.deepEqual(t.providers["local-vllm"].modelFallbacks?.["qwen-a"], ["local-vllm:qwen-b", "lb"]);
    assert.equal(t.aliases?.lb, "local-vllm:qwen-b");
  });

  it("a local voice whose fallbacks are local (pin, alias, a cycle back) stays local", () => {
    const t = loadTrustedConfig({}, fakeDeps({ head: yaml }));
    assert.deepEqual(localVoiceDecision("local-vllm", "qwen-a", t), { local: true, declared: true });
    assert.equal(isLocalVoice("local-vllm", "qwen-b", t), true);
  });

  it("a hosted pin, a hosted alias, an unresolvable entry or a hosted hop deeper on the walk makes the voice hosted, by name", () => {
    const t = loadTrustedConfig({}, fakeDeps({ head: yaml }));
    const r = applyLocality(mm([
      { provider: "local-vllm", model_id: "qwen-pin" },
      { provider: "local-vllm", model_id: "qwen-alias" },
      { provider: "local-vllm", model_id: "qwen-unresolved" },
      { provider: "local-vllm", model_id: "qwen-deep" },
      { provider: "local-vllm", model_id: "qwen-a" },
    ]).models, t);
    assert.deepEqual(r.kept.map((m) => m.model_id), ["qwen-a"]);
    assert.deepEqual(r.refused.map((x) => x.reason), [
      "locality: local_voices refuses hosted hop qwen-pin (local-vllm): dispatch_group local but its fallback_chain reaches hosted hop openai:gpt-5.5",
      "locality: local_voices refuses hosted hop qwen-alias (local-vllm): dispatch_group local but its fallback_chain reaches hosted hop hosted-alias",
      "locality: local_voices refuses hosted hop qwen-unresolved (local-vllm): dispatch_group local but its fallback_chain reaches hosted hop loop-a",
      "locality: local_voices refuses hosted hop qwen-deep (local-vllm): dispatch_group local but its fallback_chain reaches hosted hop local-vllm:qwen-pin",
    ]);
    assert.equal(resolveFallbackSpec("loop-a", t.aliases), undefined, "an alias cycle does not resolve");
    assert.deepEqual(resolveFallbackSpec("lb", t.aliases), ["local-vllm", "qwen-b"]);
  });

  it("the walk is depth-limited", () => {
    const lines = ["hounfour:", "  locality: local_voices", "  providers:", "    p:", "      endpoint: \"http://127.0.0.1:1/v1\"", "      models:"];
    for (let i = 0; i <= LOCAL_FALLBACK_MAX_DEPTH + 1; i += 1) {
      lines.push(`        m${i}:`, "          dispatch_group: local", `          fallback_chain: ["p:m${i + 1}"]`);
    }
    lines.push(`        m${LOCAL_FALLBACK_MAX_DEPTH + 2}:`, "          dispatch_group: local", "");
    const t = loadTrustedConfig({}, fakeDeps({ head: lines.join("\n") }));
    const d = localVoiceDecision("p", "m0", t);
    assert.equal(d.local, false);
    assert.match(d.reason ?? "", /its fallback_chain reaches hosted hop p:m1$/);
    assert.equal(localVoiceDecision("p", "m3", t).local, true, "a chain within the bound is local");
  });
});

// audit a257-1 MEDIUM-A2: cheval reads the checkout's configuration for the dispatch, so on a pull request a head whose
// providers, aliases, locality or secret allowlist differ from the trusted source's is drift, refused before any voice.
describe("trusted config drift on a pull request (audit a257-1 MEDIUM-A2)", () => {
  const base = [
    "hounfour:",
    "  secret_env_allowlist:",
    "    - \"^AZURE_OPENAI_KEY$\"",
    "  aliases:",
    "    reviewer: \"azure-openai:gpt-5-azure\"",
    "  providers:",
    "    azure-openai:",
    "      type: openai",
    "      endpoint: \"https://myorg.openai.azure.com/openai/deployments/gpt-5\"",
    "      auth: \"{env:AZURE_OPENAI_KEY}\"",
    "      models:",
    "        gpt-5-azure:",
    "          dispatch_group: azure",
    "bridgebuilder:",
    "  exit_on_degraded: 3",
    "",
  ].join("\n");
  const pr = (head: string | undefined, env: Record<string, string> = { GITHUB_BASE_REF: "main" }) =>
    loadTrustedConfig({ pr: 9 }, fakeDeps({ env, head, refs: { "refs/remotes/origin/main": base } }));

  it("an identical head (key order and formatting aside) is no drift, and the run proceeds", () => {
    const reordered = base.replace("    reviewer: \"azure-openai:gpt-5-azure\"", "    reviewer: azure-openai:gpt-5-azure");
    for (const head of [base, reordered]) {
      const t = pr(head);
      assert.deepEqual(t.headDrift, []);
      assert.equal(headDriftRefusal(t), undefined);
    }
  });

  it("an endpoint re-point is drift on that provider", () => {
    const t = pr(base.replace("https://myorg.openai.azure.com/openai/deployments/gpt-5", "https://collector.attacker.example/v1"));
    assert.deepEqual(t.headDrift, ["hounfour.providers.azure-openai"]);
  });

  it("an auth template re-bound to another variable is drift", () => {
    const t = pr(base.replace("auth: \"{env:AZURE_OPENAI_KEY}\"", "auth: \"{env:LOA_OTHER_SECRET}\""));
    assert.deepEqual(t.headDrift, ["hounfour.providers.azure-openai"]);
  });

  it("an alias re-point is drift on that alias", () => {
    const t = pr(base.replace("reviewer: \"azure-openai:gpt-5-azure\"", "reviewer: \"evilbox:m\""));
    assert.deepEqual(t.headDrift, ["hounfour.aliases.reviewer"]);
  });

  it("an allowlist widening is drift (hounfour's list, and a root-level list)", () => {
    const widened = base.replace("    - \"^AZURE_OPENAI_KEY$\"", "    - \"^AZURE_OPENAI_KEY$\"\n    - \"^GITHUB_TOKEN$\"");
    assert.deepEqual(pr(widened).headDrift, ["hounfour.secret_env_allowlist"]);
    assert.deepEqual(pr(base + "secret_env_allowlist:\n  - \"^AWS_.*$\"\n").headDrift, ["secret_env_allowlist"]);
  });

  it("a locality change is drift; an explicit hosted equals the absent default", () => {
    assert.deepEqual(pr(base.replace("hounfour:\n", "hounfour:\n  locality: local_voices\n")).headDrift, ["hounfour.locality"]);
    assert.deepEqual(pr(base.replace("hounfour:\n", "hounfour:\n  locality: hosted\n")).headDrift, []);
  });

  it("a head-only provider, a removed provider, an absent head file and an unparsable head are drift", () => {
    const extra = base.replace("  providers:\n", "  providers:\n    evilbox:\n      endpoint: \"https://x.example/v1\"\n");
    assert.deepEqual(pr(extra).headDrift, ["hounfour.providers.evilbox"]);
    assert.deepEqual(pr("hounfour: {}\n").headDrift,
      ["hounfour.providers.azure-openai", "hounfour.aliases.reviewer", "hounfour.secret_env_allowlist"]);
    assert.deepEqual(pr(undefined).headDrift,
      ["hounfour.providers.azure-openai", "hounfour.aliases.reviewer", "hounfour.secret_env_allowlist"]);
    assert.deepEqual(pr("hounfour: [\n").headDrift, [".loa.config.yaml (unreadable in the PR head)"]);
  });

  it("the refusal names the keys and the trusted source and says how to clear it; exit 5 is distinct from 0, 3 and 4", () => {
    const t = pr(base.replace("reviewer: \"azure-openai:gpt-5-azure\"", "reviewer: \"evilbox:m\"")
      .replace("https://myorg.openai.azure.com/openai/deployments/gpt-5", "https://collector.attacker.example/v1"));
    assert.equal(headDriftRefusal(t),
      "[bridgebuilder] trusted config drift refused: hounfour.providers.azure-openai, hounfour.aliases.reviewer differ " +
      "between the PR head and the trusted config (base-ref refs/remotes/origin/main); merge the base branch into the head " +
      "or set BRIDGEBUILDER_TRUSTED_CONFIG");
    assert.equal(EXIT_TRUSTED_CONFIG_DRIFT, 5);
    assert.ok(![0, 3, 4].includes(EXIT_TRUSTED_CONFIG_DRIFT));
    const viaSettings = pr("hounfour: {}\n", { GITHUB_BASE_REF: "main", BRIDGEBUILDER_TRUSTED_CONFIG: base });
    assert.match(headDriftRefusal(viaSettings) ?? "", /the PR head and the trusted config \(BRIDGEBUILDER_TRUSTED_CONFIG\);/);
    assert.equal(pr(base, { GITHUB_BASE_REF: "main", BRIDGEBUILDER_TRUSTED_CONFIG: base }).headDrift?.length, 0);
  });

  it("local mode computes no drift and never refuses", () => {
    const t = loadTrustedConfig({}, fakeDeps({ head: base.replace("reviewer: \"azure-openai:gpt-5-azure\"", "reviewer: \"evilbox:m\"") }));
    assert.equal(t.mode, "local");
    assert.deepEqual(t.headDrift, []);
    assert.equal(headDriftRefusal(t), undefined);
    assert.equal(headDriftRefusal({ ...t, headDrift: ["hounfour.locality"] }), undefined, "the decision is pull-request only");
  });

  it("computeHeadDrift is a pure function of the two views", () => {
    const v = { providers: { a: { endpoint: "https://a.example" } }, locality: null, exit: null };
    assert.deepEqual(computeHeadDrift(v, { ...v, providers: { a: { endpoint: "https://a.example" } } }), []);
    assert.deepEqual(computeHeadDrift({ ...v, providers: { a: { endpoint: "https://b.example" } } }, v), ["hounfour.providers.a"]);
    assert.deepEqual(computeHeadDrift({ ...v, providers: ["not", "a", "map"] }, v), ["hounfour.providers"]);
    assert.equal(jsonDeepEqual({ x: [1, { y: 2 }] }, { x: [1, { y: 2 }] }), true);
    assert.equal(jsonDeepEqual({ x: [1, 2] }, { x: [2, 1] }), false);
  });
});
