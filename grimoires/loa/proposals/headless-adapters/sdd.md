# SDD — Cheval Headless: Baseline Refactor + AGV Migration

> Design for `prd.md` (this dir). Grounded in a read of base.py + the 5 headless
> adapters + the registry (2026-06-19). Citations are `file:line` into
> `.claude/adapters/loa_cheval/`.

## 1. Architecture overview

Today: `ProviderAdapter` (base.py) → 5 sibling headless adapters, each a ~75% clone (2,766 ln). `base.py` ALREADY owns the subprocess/env plumbing — `build_headless_subprocess_env()` (base.py:527, strips creds #879/#880), `run_subprocess_pgkill()` (base.py:690, process-group kill #982), `enforce_context_window`, `estimate_tokens`. So the clones duplicate the *adapter-level* scaffolding, not the plumbing.

Target — insert one intermediate layer:

```
ProviderAdapter (base.py — subprocess/env/context plumbing; unchanged)
        └── HeadlessCLIAdapter  (NEW — the shared adapter template)
                ├── ClaudeHeadlessAdapter      (subclass: ~120 ln)
                ├── CodexHeadlessAdapter        (subclass)
                ├── CursorHeadlessAdapter       (subclass)
                ├── AgyHeadlessAdapter          (subclass — was Gemini; now shells `agy`)
                └── GrokHeadlessAdapter         (subclass)
```

## 2. `HeadlessCLIAdapter` base (R8 — FR-1)

**Final methods (lifted verbatim — proven identical across all 5):**

| Method | Source (identical across 5) | Note |
|---|---|---|
| `complete()` | claude:117–224 (template, 9 steps) | the 9-step template: get_model_config → enforce_context_window → `_build_prompt` → `_build_command` → `_compute_timeout` → acquire semaphore → `run_subprocess_pgkill` → classify errors → `_parse_output`. Only the hooks vary. |
| `_build_prompt()` | claude:386–421 | byte-identical role-prefixed flatten |
| `validate_config()` | claude:226–245 | provider-type + binary-on-PATH |
| `health_check()` | claude:247–262 | `<bin> --version`, rc==0 |
| `_compute_timeout()` | claude:376–380 | floors via class attrs `_CONNECT_FLOOR`/`_READ_FLOOR` |
| semaphore + subprocess + 4 error raises (Timeout/OutputCap/FileNotFound/SemaphoreExhausted) | all 5 | parameterized by `_provider_label()` |
| `_resolve_effort()` | claude/codex/grok ~identical | subclass overrides `_ALLOWED_EFFORTS`; cursor/agy set it empty (no effort concept) |
| binary resolution | `_<bin>()` x5 | one `_cli_binary()` reading class attrs `_BIN_DEFAULT` + `_BIN_ENV` |

**Abstract hooks (the only per-provider surface, ~120 ln/subclass):**
- `_build_command(request, model_config, prompt) -> list[str]` — the CLI argv.
- `_parse_output(stdout, ...) -> CompletionResult` — provider output shape.
- `_raise_for_error(stdout, stderr, returncode)` — provider rate-limit/auth markers.

**Class attributes (replace the per-adapter `_*_BIN_DEFAULT` consts):**
`_BIN_DEFAULT`, `_BIN_ENV`, `_CONNECT_FLOOR=10`, `_READ_FLOOR=600`, `_ALLOWED_EFFORTS`, `_PROMPT_TRANSPORT ∈ {argv, stdin, file}`.

**`_PROMPT_TRANSPORT`** captures the one real divergence the base must parameterize: claude/gemini pass prompt on **argv** (gemini:278 — ARG_MAX cliff on big diffs), codex/cursor via **stdin**, grok via **--prompt-file**. The base's `complete()` routes the prompt to argv/stdin/file by this attr.

## 3. Declarative registry table (R1 — FR-3)

Today: an imperative dict (`__init__.py:50–54`) + `get_adapter()` factory (`:58`) + `cli_adapter_types()` (`:66`, auto-admits `auth_type=="headless"`), with terminal facts scattered in `model-config.yaml` per provider.

Target: ONE declarative table (the R1 "single source"), e.g. `providers/headless_registry.py`:

```python
HEADLESS_TERMINALS = {
  "gemini-headless": HeadlessSpec(cls=AgyHeadlessAdapter, bin_default="agy",  bin_env="AGY_HEADLESS_BIN",  prompt_transport="argv"),  # spike T4.1: agy is -p argv; no --prompt-file exists
  "claude-headless": HeadlessSpec(cls=ClaudeHeadlessAdapter, bin_default="claude", ...),
  ... (codex, cursor, grok)
}
```

`_ADAPTER_REGISTRY` + `cli_adapter_types()` derive FROM this table (no second list to drift — the "#966 config-dead" root cause). A new terminal = one row.

## 4. AGV repoint (FR-5/6/7)

Decision: **repoint the existing `gemini-headless` terminal to `agy`** — keep the type string `gemini-headless` + aliases (`model-config.yaml:752`) so every config/ref resolves unchanged. The class backing it becomes `AgyHeadlessAdapter` (renamed for honesty; registry key unchanged).

**The gemini→agy delta** (what the subclass overrides vs the gemini baseline):

| Aspect | Gemini (today) | Agy (target) |
|---|---|---|
| binary | `gemini` (gemini:260) | `agy` (`_BIN_DEFAULT="agy"`, `_BIN_ENV="AGY_HEADLESS_BIN"`) |
| headless flag | `-p <prompt>` argv (gemini:278) | `agy -p` — **prompt on argv** (`_PROMPT_TRANSPORT=argv`; spike T4.1: **no `--prompt-file` flag exists** → ARG_MAX cliff PERSISTS, not fixed here) |
| auth | strips GOOGLE_API_KEY/GEMINI_API_KEY → GCA OAuth (gemini:151) | **agy OAuth** (spike T4.1: `agy models` → exit 0; **no API-key flag exists**; creds in an OAuth store, NOT `~/.agy` / NOT `GOOGLE_API_KEY`). The gemini env-strip (`_HEADLESS_STRIPPED_AUTH_VARS`, base.py:511) is **likely a no-op for agy** — verify at T4.5; do NOT assume gemini's transfers |
| output parse | `{session_id, response, stats.models.<id>.tokens}` (gemini:359–437) | **PLAIN TEXT** (spike T4.1) — agy emits no JSON / no `--output-format`; `_parse_output` is a stdout passthrough + `estimate_tokens()` (clone grok's `_build_result`, NOT gemini's JSON parser; loses real token counts) |
| error markers | gemini auth/rate strings (gemini:443–494) | **TBD — spike**; agy-specific markers |
| **non-TTY (FR-6)** | n/a | agy HANGS in non-TTY on agentic output (waits on a tool-permission prompt that never comes). **Spike-resolved (T4.1):** the `--sandbox --dangerously-skip-permissions` flags (argv) with a closed stdin (subprocess `stdin=DEVNULL`, NOT a shell redirect in the argv) → clean output, exit 0, zero ANSI/control bytes. `--sandbox` keeps it terminal-restricted (the read-only analog of gemini's `--approval-mode plan`); never `--dangerously-skip-permissions` alone on a review path. Risk **High→Low**. |

`gemini-api` (#1091, HTTP) stays as the fallback chain entry; only the CLI terminal swaps gemini→agy.

## 5. Adjacent cleanups (operator-trimmable at sprint-plan)

- **R10** — split `base.py` (891 ln, 4 concerns) by consumer group (subprocess-lib / context-lib / config-lib). Low risk; improves the base we're building on.
- **R11** — structurally guard the output-swallow class (the highest-correctness-payoff item per the R8 review). Fits naturally since we're consolidating `complete()`.

## 6. The `agy` spike (de-risks FR-5/6 — do FIRST)

Before the AgyHeadlessAdapter is written, a small spike resolves the 4 TBDs against the real `agy` CLI on the cheval host:
1. headless invocation: `agy -p` vs `--print`; prompt transport (stdin / `--prompt-file` / argv).
2. output JSON shape (→ `_parse_output`).
3. auth flow + cred env vars (→ `_HEADLESS_STRIPPED_AUTH_VARS`).
4. the non-TTY stdout behavior + the documented workaround (→ FR-6).
Output: a one-page spike note that turns the TBD rows in §4 into concrete overrides. **This gates Phase 2.**

## 7. Migration strategy (behavior-preserving)

- The **38 headless test files** (636/754/476/645/498 + shared pgkill/concurrency) are the pin: green BEFORE the base lands and AFTER each adapter migrates.
- Migrate one adapter at a time onto the base (claude first — it's the template source), tests green per step.
- R8 companion: collapse the 5 clone suites into one parametrized suite (inject `adapter_cls` + the 3 hooks + fixtures); keep per-adapter LIVE tests (gated by `LOA_*_HEADLESS_LIVE=1`).
- The agy repoint adds an agy live-smoke test (gated) that proves #1089 closed end-to-end.

## 8. Risks

| Risk | Sev | Design mitigation |
|---|---|---|
| agy non-TTY stdout breaks parsing (FR-6) | **High** | the §6 spike resolves it before the adapter; isolate in `_parse_output` + a forced-non-interactive flag in `_build_command` |
| agy auth not establishable headless on host | Med | spike step 3 verifies; document in headless-mode runbook; gemini-api stopgap covers until then |
| base extraction regresses one adapter's quirk (cursor envelope-preamble, codex JSONL, grok prompt-file) | Med | hooks isolate quirks; 38 tests pin; migrate one-at-a-time |
| ARG_MAX cliff on huge diffs (agy is argv like gemini; no `--prompt-file`) | Low | **unchanged** from gemini per spike T4.1 — NOT fixed here; the `gemini-api` HTTP fallback (§4) covers oversized diffs |

## 9. Out of scope

Phase 3 (GLM-5.2 via a new OpenRouter `kind:http` provider — NOT a headless clone) is a separate plan. The R1 table + HeadlessCLIAdapter base built here make a *headless* GLM trivial later, but GLM-via-OpenRouter is an HTTP-adapter path, unaffected by this SDD.
