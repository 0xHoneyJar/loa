# curl-Mock Harness — Operator Runbook

## Background

The curl-mock harness is the execution-level test substrate named by Bridgebuilder iter-4 REFRAME-1 (cycle-102 sprint-1A) and reaffirmed by BB iter-2 REFRAME-2 (sprint-1B, vision-024). It replaces awk-based static-grep tests against bash adapter functions (which DISS-001/002/003 BLOCKING flagged) with hermetic, fixture-driven assertions about the actual HTTP call shapes adapters produce.

**What it does:**
- Places a `curl` shim earlier on `PATH` than `/usr/bin/curl` for the duration of a test
- Records `argv` + `stdin` to a JSONL call log
- Emits a configured response (status code + headers + body) per a fixture YAML file
- Supports success, 4xx, 5xx, disconnect, timeout failure modes via fixture taxonomy

**What it does NOT do:**
- Replace real-network smoke tests in the `Model Health Probe (PR-scoped)` workflow — that gate is intentionally end-to-end and runs against live providers.
- Generate fixtures from real responses — hand-curated fixtures only for sprint-1C; codegen is sprint-3+ if warranted.

**Origin:** Issue [#808](https://github.com/0xHoneyJar/loa/issues/808). Pattern source: `feedback_bb_plateau_via_reframe.md`. Predecessor handoff: `grimoires/loa/cycles/cycle-102-model-stability/handoffs/sprint-1-bb-plateau.md` § "Sprint-2 backlog".

## Mechanics

### PATH ordering

The shim activates by:
1. Creating a tempdir (typically `$BATS_TEST_TMPDIR/curl-mock-bin`)
2. Symlinking `curl` in that tempdir to `tests/lib/curl-mock.sh`
3. Prepending the tempdir to `PATH`

When `curl` is invoked, the shell's `PATH` lookup finds our shim before `/usr/bin/curl`. Teardown restores the original `PATH`.

**Hermetic guarantee:** the shim refuses to run without both `LOA_CURL_MOCK_FIXTURE` and `LOA_CURL_MOCK_CALL_LOG` env vars. There is no fall-through to real curl. Missing fixture file is exit code 99 with a fail-loud stderr message — exactly the anti-silent-degradation discipline named by vision-019/023.

### Environment variables

| Variable | Required | Description |
|----------|----------|-------------|
| `LOA_CURL_MOCK_FIXTURE` | yes | Path (absolute or relative to fixture dir) to fixture YAML |
| `LOA_CURL_MOCK_CALL_LOG` | yes | Path to JSONL call-log file (created if absent) |
| `LOA_CURL_MOCK_DEBUG` | no | Set to `1` to emit shim-trace lines to stderr |

### Call log format (JSONL)

One entry per `curl` invocation, appended atomically:

```json
{"ts": "2026-05-09T22:30:00Z",
 "argv": ["curl", "-X", "POST", "-d", "@-", "https://api.openai.com/..."],
 "stdin": "{\"model\":\"gpt-5.5-pro\",\"max_output_tokens\":32000}",
 "fixture": "/.../tests/fixtures/curl-mocks/openai-success.yaml",
 "exit_code": 0,
 "status_code": 200}
```

## Helper API

Source via `load '../lib/curl-mock-helpers'` from a bats test. All helpers documented in `tests/lib/curl-mock-helpers.bash`.

### Lifecycle

| Helper | Call from | Purpose |
|--------|-----------|---------|
| `_setup_curl_mock_dirs` | `setup()` | Creates per-test tempdir + call log |
| `_teardown_curl_mock` | `teardown()` | Restores `PATH`; unsets env; returns 0 |
| `_with_curl_mock <fixture-name>` | inside `@test` | Activates the shim with the named fixture |

### Assertions

| Helper | Asserts |
|--------|---------|
| `_assert_curl_called_n_times <N>` | Total invocation count equals `N` |
| `_assert_curl_payload_contains <substring>` | Substring appears in `stdin` of at least one call |
| `_assert_curl_argv_contains <substring>` | Substring appears in `argv` of at least one call |

### Introspection

| Helper | Returns |
|--------|---------|
| `_curl_mock_call_count` | Echo total call count to stdout |
| `_curl_mock_call_log_path` | Echo absolute path to JSONL log |

## Fixture format

Fixtures live under `tests/fixtures/curl-mocks/`. YAML schema:

| Field | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| `status_code` | int 100-599 | yes | — | HTTP status code |
| `exit_code` | int | no | 0 | Curl exit code (28=timeout, 7=disconnect) |
| `delay_seconds` | int | no | 0 | Sleep before response (simulates slow response) |
| `headers` | map | no | `{}` | Header-name → value (only emitted with `-i`) |
| `body` | string | no | "" | Inline body — mutually exclusive with `body_file` |
| `body_file` | path | no | "" | Relative to fixture's dir, or absolute |
| `stderr` | string | no | "" | Written to stderr verbatim (suppressed by `-s`) |

### Reference fixtures provided

| Fixture | Status | Purpose |
|---------|--------|---------|
| `200-ok.yaml` | 200 | Generic success |
| `400-bad-request.yaml` | 400 | Invalid request |
| `401-unauthorized.yaml` | 401 | Auth failure |
| `429-rate-limited.yaml` | 429 | Rate limit (with `retry-after`) |
| `500-internal.yaml` | 500 | Server error |
| `503-unavailable.yaml` | 503 | Service unavailable |
| `disconnect.yaml` | — | Curl exit 7 (CURLE_COULDNT_CONNECT) |
| `timeout.yaml` | — | Curl exit 28 (CURLE_OPERATION_TIMEDOUT) |
| `openai-success.yaml` | 200 | OpenAI provider-shaped response (loads `bodies/openai-success.json`) |
| `anthropic-success.yaml` | 200 | Anthropic provider-shaped response |
| `google-success.yaml` | 200 | Google provider-shaped response |

## Usage examples

### Basic: assert adapter binds payload field correctly

```bash
load '../lib/curl-mock-helpers'

setup() { _setup_curl_mock_dirs; }
teardown() { _teardown_curl_mock; }

@test "openai adapter binds max_output_tokens" {
    _with_curl_mock openai-success
    run my-adapter --provider openai --model gpt-5.5-pro --max-output 32000
    [ "$status" -eq 0 ]
    _assert_curl_called_n_times 1
    _assert_curl_payload_contains '"max_output_tokens":32000'
}
```

### Multi-call: retry behavior

```bash
@test "adapter retries 3 times on 429" {
    _with_curl_mock 429-rate-limited
    run my-adapter --provider openai
    [ "$status" -ne 0 ]  # adapter eventually fails
    _assert_curl_called_n_times 3
}
```

### Error-class mapping (cheval _error_json shape)

```bash
@test "cheval maps timeout to TIMEOUT error_class" {
    _with_curl_mock timeout
    run cheval invoke --provider openai --model gpt-5.5-pro
    [ "$status" -ne 0 ]
    [[ "$output" == *'"error_class":"TIMEOUT"'* ]]
}
```

## Gotchas

### `set -e` and teardown

bats teardown runs under `set -e`. The previous-generation pattern `[[ -d "$dir" ]] && rm -rf "$dir"` returns false (exits non-zero) when the test invoked `skip`. Use the explicit form per `feedback_harness_lessons.md`:

```bash
teardown() {
    if [[ -n "${_CURL_MOCK_BIN_DIR:-}" ]]; then
        rm -rf "$_CURL_MOCK_BIN_DIR"
    fi
    return 0
}
```

The harness's `_teardown_curl_mock` already handles this — but if you build custom teardown, mirror the pattern.

### Hermetic test isolation

Each test gets a fresh tempdir via `BATS_TEST_TMPDIR`. Do NOT cache the shim path or call-log path across tests. `_setup_curl_mock_dirs` re-initializes them per test.

### Parallel bats

The harness is parallel-bats safe: each test gets its own `BATS_TEST_TMPDIR`, so the shim symlinks and call logs never collide. Concurrent tests that activate the shim with different fixtures will not interfere.

### NEVER use in production

The shim is a TEST-ONLY artifact. The `Model Health Probe (PR-scoped)` workflow MUST run against real providers — that gate exists specifically to catch regressions the mock cannot. CI workflows that run sprint-1C tests must NOT extend the harness's PATH activation past test boundaries.

If you find yourself wanting to mock `curl` in a production CI check, file an issue first — the answer is almost certainly "no" and the question itself is a sign you're in the wrong scope.

### Multiline body and yq

The shim's YAML parser uses `yq` (Mike Farah's v4) when available. Without `yq`, the fallback grep-based parser handles only top-level scalar fields — multiline `body:` requires `yq`. The repo's BATS Tests workflow installs `yq` via the existing pin in cycle-099 codegen-toolchain runbook.

### Provider-specific response shapes

The `bodies/openai-success.json`, `bodies/anthropic-success.json`, and `bodies/google-success.json` fixtures hand-mirror the real provider response schemas as of 2026-05-09. When provider APIs evolve (e.g., new `output[].type` values, new usage-metric fields), update these fixtures alongside the adapter changes — the substrate-speaks-twice pattern from vision-024 says: a stale fixture passes the test but masks a real-world change.

## Related

- Issue [#808](https://github.com/0xHoneyJar/loa/issues/808) — sprint-2 (now sprint-1C) curl-mocking harness
- vision-024 "The Substrate Speaks Twice" — `grimoires/loa/visions/entries/vision-024.md`
- BB iter-4 REFRAME-1 (cycle-102 sprint-1A PR #803) — origin
- BB iter-2 REFRAME-2 (cycle-102 sprint-1B PR #813) — reaffirmation
- `feedback_bb_plateau_via_reframe.md` — plateau-detection pattern
- `feedback_harness_lessons.md` — bats teardown discipline (closes the `&&`-chained pattern that produced 32 spurious `not ok # skip` lines on Sprint 1A's CI)

— cycle-102 Sprint 1C T1C.8, 2026-05-09
