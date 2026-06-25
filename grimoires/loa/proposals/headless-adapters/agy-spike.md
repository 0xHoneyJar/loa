# Spike note — `agy` (Antigravity CLI) headless contract  (sprint T4.1)

> Run 2026-06-19 against the real `agy` v1.0.9 (`/Users/zksoju/.local/bin/agy`) on the
> cheval host. Resolves the 4 TBDs in `sdd.md` §4/§6. **GATE for T4.2–T4.6: PASSED.**

## Answers to the 4 spike questions

**(a) Invocation** — `agy -p "<prompt>" --model "<label>" --sandbox --dangerously-skip-permissions </dev/null`
- `-p` / `--print` / `--prompt` = "run a single prompt non-interactively and print the response". Prompt is the **argv value** after `-p` (NOT stdin, NOT a file — same as gemini today → **ARG_MAX cliff persists** for huge diffs; no `--prompt-file` flag exists).
- `--model "<label>"` takes the **human-readable label** from `agy models`, e.g. `"Gemini 3.1 Pro (High)"` — NOT an API id. (`extra.cli_model` must be a label.)
- `--print-timeout` default **5m** (relevant to `_compute_timeout`).

**(b) Output shape** — **PLAIN TEXT.** `agy -p "Reply with exactly: OK"` → `OK\n` (3 bytes). **No JSON, no usage/token stats, no `--output-format json` flag exists.** → the agy `_parse_output` reads stdout as the content directly and derives usage via `estimate_tokens()` — i.e. it mirrors **grok's `_build_result`** pattern, NOT gemini's JSON-stats parser. (Simpler than gemini; loses real token counts.)

**(c) Auth** — agy is **OAuth-authed** on this host (`agy models` → exit 0, lists models). No API-key flag; creds are NOT in `~/.agy` / `~/.antigravity` (OAuth store elsewhere). agy does not appear to depend on `GOOGLE_API_KEY` → the gemini `_HEADLESS_STRIPPED_AUTH_VARS` logic is likely a no-op for agy (verify at T4.5; don't assume the gemini env-strip transfers).

**(d) Non-TTY (FR-6) — the gotcha is REAL, and SOLVED.**
- Trivial output ("OK") returns clean in non-TTY. **Non-trivial/agentic output HANGS** in non-TTY (a multi-line "list 1–5" hung >3 min until killed) — agy is a coding *agent* and waits on a **tool-permission prompt** that never comes without a TTY.
- **Fix (grounded):** `--dangerously-skip-permissions` + `</dev/null` → clean multi-line output, exit 0, **zero ANSI/control bytes**.
- **Safety:** `--dangerously-skip-permissions` alone auto-approves *tool execution* — a footgun for a review/completion path. **Pair it with `--sandbox`** (terminal-restricted; the analog of gemini's read-only `--approval-mode plan`). Verified: `--sandbox --dangerously-skip-permissions </dev/null` → clean, exit 0.

## Bonus findings (feed the SDD)

- **agy is a MULTI-MODEL gateway**, not Google-only: `agy models` lists Gemini 3.5 Flash (L/M/H), Gemini 3.1 Pro (L/H), **Claude Sonnet 4.6**, **Claude Opus 4.6**, **GPT-OSS 120B**.
  - The repoint uses agy's **Gemini** models → preserves the Google-lineage voice for `gemini-headless`.
  - ⚠️ **Do NOT route the Anthropic flatline voice through agy** — that would break company-independence (Claude-via-Google's-Antigravity is not a genuinely independent voice). Keep agy scoped to its Gemini models for the repoint.

## Resulting deltas to the plan

| SDD/sprint item | Spike resolution |
|---|---|
| `_build_command` (T4.2) | `agy -p <prompt> --model <label> --sandbox --dangerously-skip-permissions`; stdin closed (`</dev/null`); `_PROMPT_TRANSPORT=argv` |
| `_parse_output` (T4.2) | plain-text passthrough + `estimate_tokens()` (clone grok's `_build_result`, not gemini's JSON parser) |
| FR-6 non-TTY (T4.3) | **solved** — the flag combo above; risk downgraded High → Low |
| auth env-strip (T4.5) | gemini's GOOGLE_API_KEY strip likely a no-op for agy (OAuth); verify, don't assume |
| `extra.cli_model` (T4.4) | a label string e.g. `"Gemini 3.1 Pro (High)"` |
| ARG_MAX | unchanged — agy is argv-transport like gemini; huge-diff cliff remains (no `--prompt-file`) |

**Net:** FR-6 (the one High risk) is de-risked to a known flag combo. T4.2–T4.6 can proceed.
