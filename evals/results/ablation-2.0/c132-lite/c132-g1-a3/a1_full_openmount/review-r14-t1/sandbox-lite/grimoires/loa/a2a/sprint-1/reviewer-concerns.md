# Reviewer concerns — sprint-1 (PR: cycle-126 sprint-250 tasks 4.1–4.8)

Scope: `pr/head.diff` (88 files). Cite as `head/<path>:<line>`.

## Areas I want a second opinion on

1. `head/.claude/hooks/compliance/implement-gate.sh` — the new evidence recorder (lines ~35-50) runs before the file_path check and writes `.run/platform-features.json` via mktemp+mv; the authoritative mode is now selected only by `.loa.config.yaml implement_gate.mode`, yet that branch still trusts the model-authored `tool_input.active_skill` field to ALLOW App-Zone writes. Is the opt-in sufficiently fenced? Any race / partial-write / jq-argjson quoting issue in the recorder (`${_ig_base:-{\}}`)?
2. `head/.claude/scripts/detect-platform-features.sh` — the 1-hour cache returns early on a file the gate recorder wrote (which lacks `schema_version`, `detected_at`, `harness_signal`). Any consumer that reads those keys?
3. `head/.claude/scripts/check-permissions.sh` — new `rule_key` grammar: `Bash(<body>)` with one trailing `:*` or ` *` stripped. Does this match Claude Code's actual rule semantics (is `Bash(git push *)` a wildcard in Claude Code)? Latent: `base` for an exact-key requirement (`=foo bar`) becomes `*=foo` — unreachable today since all requirements are wildcard, but check.
4. `head/evals/graders/recall-vs-defects.sh` — the new CITE regex: a bare `:N` binds to the most recent cited path anywhere earlier in the document; `(` stripped from the path start; `head:N`/`base:N` forms. Any over-crediting or false-credit path? Any catastrophic-backtracking risk?
5. `head/.claude/defaults/model-config.yaml` — `claude-opus-5-5` carries no `long_context` pricing tier (vendor page: 4.6+ at standard pricing) while `claude-opus-5` in the same catalog still carries a 2.0×/1.5× tier above 200K. Internal inconsistency; is any cost code affected?
6. `head/.claude/loa/CLAUDE.loa.md` — file is 10,225 B against the new 10,240 B budget (15 bytes of headroom); the `@loa-managed` hash header changed — is it computed correctly?
7. `head/.claude/data/agent-types.yaml` — is the write-capable list complete for every `.claude/agents/*.md` the test SC-T-AGENT-7 iterates?
8. `head/.claude/scripts/model-adapter.sh` — stderr of cheval now captured to a mktemp file under `set -euo pipefail`; only the agy WARN is forwarded. Any leak of the temp file or failure mode when TMPDIR is unwritable?
9. `head/.claude/scripts/flatline-proposal-review.sh`, `flatline-validate-learning.sh`, `flatline-learning-extractor.sh` — defaults changed from literal OpenAI ids (`gpt-4o`, `gpt-4o-mini`, `claude-3-opus-*`) to catalog aliases (`reviewer`, `opus`, `cheap`). They flow through `call_flatline_chat` → model-invoke, which resolves aliases. Any path where a literal provider id was required?
10. No `CHANGELOG.md` change in the 88 files even though the last commit message references a CHANGELOG figure.
11. `head/tests/unit/implement-gate.bats` IG-11 asserts `implement_gate` is undocumented in docs/ and the example config — an undocumented security-relevant opt-in.
