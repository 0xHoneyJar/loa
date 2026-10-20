# Implementer C — Sprint 263 Task 1.8: dissent numeric anchors and budget_scale

## What was built
- **Numeric anchors** (`.claude/scripts/adversarial-review.sh`): the review and audit prompts both show `"anchor_line": <int, the head line the finding sits on>, "anchor_line_end": <int, optional, for a range>` beside `anchor`/`anchor_type`, plus the sentence "Give `anchor_line` whenever the finding sits on a specific line; keep `anchor` as `file:symbol`." The stable-anchor rule for high severities is unchanged. The jq filter `_ADV_NUMERIC_ANCHOR_JQ` runs first in `_normalize_finding_for_validation`. It keeps a line only as a whole number from 1 to 10,000,000, and an end only beside a kept start and at least it. Other values are dropped silently, never a rejection or repair. On the schema-enforced branch it runs only when the keys are present, so it also drops the nulls a strict voice sends. `validate_anchor`, `anchor_stability` and the hallucination filter key on `anchor` alone.
- **budget_scale** (same script): `_adv_conf_budget_scale` reads `budget_scale` (fixed|diff, tag-checked) and `budget_cents_max` (default 600). A malformed value logs a WARN and gives `fixed`. `_adv_budget_effective` computes `min(max(budget, ceil(est×1.2)), max)` in integer arithmetic. The gate compares the estimate against the effective budget. When the key is written, the envelope carries `budget_scale`, `budget_cents_effective` and `budget_cents_max`, and a refusal adds `reason: "budget"`. With the key absent the envelope is byte-identical to before. The header comment documents both.
- **Schemas**: `adversarial-finding.schema.json` gains optional integers `anchor_line` and `anchor_line_end` with `minimum: 1`, plus the three metadata fields. `.claude/schemas/wire/dissent-review.wire.json` and `.claude/schemas/wire/dissent-audit.wire.json` gain both fields as `anyOf [integer, null]`, listed in `required`, with nothing else changed (lead authorization, second round).
- **Docs and config**: an identical section is appended to both `ADVERSARIAL-REVIEW.md` resources (CMP-138 holds their shared tail byte-identical). `.loa.config.yaml.example` sets `budget_scale: fixed` and `budget_cents_max: 600` under both gates, with the formula and the note that the harness writes `diff`.
- **Tests**: the new `tests/unit/adversarial-review-budget-scale.bats` has BSC-1..10. `adversarial-review-normalise.bats` gains NRM-68..74, and its NRM-46 argv allowlist gains the four new scalars.
- **Separate fixture patch** `~/.cache/loa/cycle-131/patches/s1-c-fixtures.patch` is outside my ownership, so I did not apply it in the worktree. It adds `"anchor_line": null, "anchor_line_end": null` to 5 kf004 fixtures (audit-all-severities, audit-critical, review-advisory-anchorless, review-blocking, neg-missing-id). It is a one-line change per file, and `git apply --check` passes on the worktree.

## How it was tested
```
bash -c '~/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats tests/unit/adversarial-review-*.bats tests/unit/verdict-derive.bats'
(cd .claude/adapters && python3 -m pytest -q tests/)
```
- First round, before the wire change, on the worktree: **556/556 ok**. Counts: budget-scale 10, normalise 73, companion 284, verdict-derive 75, repair-loop 25, hallucination 21, schema-enforced 14, verdict-quality 13, kf-011 11, locality 10, advisory 9, budget 7, degraded-on-rejection 4.
- Also green in round one: wire-schemas-api-safe, adversarial-review.bats and cycle-124-dispatch-budgets (95 ok), plus the 12 suites that read the example config (112 ok).
- Wire round: the worktree plus the fixture patch, on a full scratch copy, is reported in WIRE-VERIFY below. On the worktree alone, without the fixture patch, FR7-10 (schema-enforced) and 4 cases of `test_structured_outputs_fixtures_wire_valid.py` fail. Those fixtures lack the now-required keys. Apply both patches together.
- `tests/integration/adversarial-review-e2e.bats` fails cases 1, 3 and 4 the same way on a pristine HEAD export. The failures predate this change.
- Test-first: NRM-74 and BSC-9 were red before their edits. The other cases were written after the code.

## AC evidence
- FR-4 AC1, prompt and normaliser: PASS. NRM-73 checks both prompts. NRM-68 keeps the lines, and its symbol-only twin is equal minus the keys. NRM-69 drops non-integers with no repair. NRM-70 shows the symbol-only output is byte-identical to the old normaliser. NRM-71 covers the enforced branch, nulls dropped.
- FR-4 AC1, schemas: PASS. NRM-72 validates the finding schema with and without the fields. NRM-74 checks that each wire schema accepts integer or null lines, rejects a finding missing the keys or carrying a string or float, and is otherwise unchanged. The wire-schema checks W1–W5 pass, including the W4 severity-enum marker test.
- FR-4 AC1, verdict-derive unaffected: PASS (75/75, file untouched).
- FR-4 AC1, scaled budget and maximum: PASS. BSC-1: absent key, 366c against 200c refused, the old five metadata keys exactly. BSC-3: diff, 214c against 200c gives 257 and the review runs. BSC-4: 700c is capped at 600 and refused with reason budget. BSC-5 and 6 cover malformed values falling back to fixed. BSC-7 covers the formula branches. BSC-8 shows each gate reads its own block. BSC-10 shows the fields survive the companion fold.
- FR-4 AC2, example config and shipped default `fixed`: PASS (BSC-9, which also checks the live config is untouched). The eval config setting `diff` is implementer A's work. A has the key names and envelope fields.
- FR-4 AC3, smoke: the lead's step. The wire change removes the blocker for enforced voices.
- Key names exactly: `flatline_protocol.{code_review,security_audit}.{budget_scale,budget_cents_max}`.

## DECISION bullets
- DECISION: The envelope names the scaling (`budget_scale`, `budget_cents_effective`, `budget_cents_max`, plus `reason: "budget"` on a refusal) only when the `budget_scale` key is written. An absent key gives an envelope byte-identical to before. An explicit `fixed` names it.
- DECISION: The formula is applied literally. Under `diff` a `budget_cents` above `budget_cents_max` is held to the maximum. The example config comment says so.
- DECISION: "configured budget" means the effective `--budget` CLI value when given, else the config's `budget_cents`.
- DECISION: A malformed `budget_cents_max` makes the whole scale fall back to `fixed`.
- DECISION: `budget_scale` is case-sensitive. `Diff`, `yes`, a number, a list or a map are malformed, so the scale is `fixed` and a WARN is logged.
- DECISION: `anchor_line` has an upper bound of 10,000,000. An integer-valued string is dropped. An end without a kept start is dropped. end == start is kept.
- DECISION: The numeric-anchor filter also runs on the schema-enforced branch, only when a finding carries the keys. It drops the nulls that strict voices emit.
- DECISION: The audit prompt gets its own anchor shape line. It previously said only "Same field structure as code review".
- DECISION: The finding schema's metadata section documents the three budget fields. It is a documentation contract.
- DECISION: The example config writes `budget_scale: fixed` and `budget_cents_max: 600` uncommented, in the style of its siblings. A copier's envelope names the scaling, with the same behaviour.
- DECISION: The new suite uses the whole-run `adversarial-review-s3-helpers.bash` harness, the existing stub harness for the budget gate.
- DECISION: The finding-schema test lives in the normalise suite. It uses a stdlib subset validator, plus jsonschema where present. `tests/unit/adversarial-review.bats` is untouched.
- DECISION: The wire schemas `.claude/schemas/wire/dissent-review.wire.json` and `.claude/schemas/wire/dissent-audit.wire.json` are extended under the lead's authorization. Each gains `anchor_line` and `anchor_line_end` as nullable integers (`anyOf [integer, null]`) listed in `required`, not as optional `minimum: 1` integers. The lead's form fails W2 (required == properties) and W3 (no `minimum`), which pin OpenAI strict mode and the Claude CLI's `--json-schema` validator. Enforced voices would fail live. Null is the strict-mode way to say "optional", the same pattern `anchor` uses, and the normaliser drops null. `additionalProperties`, the enums and every other property and required entry are unchanged (NRM-74).
- DECISION: The 5 kf004 fixtures that must carry the now-required keys are delivered as a separate patch, `s1-c-fixtures.patch`, not edited in the worktree. They are outside my ownership list.

## What the lead must do
1. Apply `s1-c.patch` and `s1-c-fixtures.patch` together. Either one alone leaves FR7-10 and the fixture pytest red, or leaves enforced voices unable to emit lines.
2. Regenerate `.claude/checksums.json`. Six `.claude/` files changed.
3. Record the DEC row amending the System Zone list with the two wire paths. Note that it uses the nullable-required form, not the optional-`minimum` form.
4. The eval config (`budget_scale: diff` for both gates, `config_variant: eval`) and the grader reading `anchor_line` are `evals/` work.

## WIRE-VERIFY
A full scratch copy of the worktree with `s1-c-fixtures.patch` applied ran `adversarial-review-*.bats`, `verdict-derive.bats`, `wire-schemas-api-safe.bats`, `adversarial-review.bats` and `cycle-124-dispatch-budgets.bats`.
- Bats: 651/652 ok. The one failure, CMP-128, comes from the scratch copy having no HEAD ("ambiguous argument 'HEAD'"). It passes in the real worktree.
- Adapter pytest (`.claude/adapters/tests/`): 3278 passed, 3 failed. All 3 also fail on the copy without the wire change, so they predate it. Two are host artifacts (`claude` resolves to the `claude-fallback` wrapper). The third (the probe-record home path) passes in the real worktree.
- Logs: `~/.cache/loa/cycle-131/logs/s1c-wire-verify.log` and `s1c-wire-pytest.log`.
