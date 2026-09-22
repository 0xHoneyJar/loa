All good

Observations documented and non-blocking. See Observations below.

# sprint-bug-239 Review Feedback — round 1

**Reviewer:** Senior Tech Lead Reviewer Agent (Fable 5.1 lead acting as gate; independent input: cross-model dissent gpt-5.5-pro with the reviewer's seven-point concern list — `adversarial-review.json`, status `clean`, 0 findings, 0 rejected payloads)
**Date:** 2026-09-22
**Bug:** 20260922-13a3d1 — Aleph gates block Loa; make Aleph opt-in · **Plan:** `grimoires/loa/a2a/bug-20260922-13a3d1/sprint.md`
**Implementation Report:** `grimoires/loa/a2a/bug-20260922-13a3d1/reviewer.md`
**Range:** working tree over `5543b413` — 11 files outside the a2a record (one new lib, one new test suite, two scripts, one bootstrap list, three test suites, two workflows, two config files, CHANGELOG), plus regenerated REPO-MAP and checksums

---

## Overall Assessment

The bug is the one the maintainer named: a third-party component's digest check sat inside Loa's required CI and its installer inside Loa's mount path, so Loa's own lint (which required a frontmatter block in `loa-aleph/SKILL.md`) turned PR #1266 red. The fix is the smallest one that removes the coupling and nothing else, verified in the code:

- **One switch, one predicate.** `.claude/scripts/lib/aleph-opt-in.sh:25-40` — env `LOA_ALEPH_ENABLED` or the bare boolean `true` directly under the top-level `aleph:` key, read with POSIX awk; missing config, mis-scoped key, quoted string, anything else → disabled. No `yq` dependency after the audit dissent pointed out that a missing parser must never decide a gate (AO-1 and AO-5 lock it).
- **Every reach-in goes through it.** `mount-submodule.sh:1379` (`aleph_refresh_is_applicable`, which `refresh_copy_set` and `update-loa.sh` already consult), `check-loa.sh:559`, the three Aleph suites' `setup()` (`skip` unless enabled), and the two workflows (`gate` job; `verify` / `prepare` / `propose` `needs: gate` + `if: needs.gate.outputs.enabled == 'true'`). Both scripts define a disabled fallback when the lib is absent (`mount-submodule.sh:512-517`, `check-loa.sh:20-25`), so an older submodule fails toward "off", not toward an error.
- **The gate cannot be flipped by the PR under review.** The integrity workflow's gate checks out the base ref's config on pull requests (`aleph-bundle-integrity.yml:45-48`); AO-5b pins it. The sync workflow runs on `main` by schedule/dispatch, where `github.sha` is the right ref.
- **Opted-in behaviour is byte-identical.** The predicate is additive in front of the existing presence logic; with `LOA_ALEPH_ENABLED=1` the framework-integration and real-installer suites run and pass 41/41.
- **Nothing Aleph-managed was touched**, and the `capabilities:` block stays (AO-7 with Loa's lint green).
- **Tests first**: AO-1/3/4/5/6 red before the lib existed; AO-2 was caught as vacuous (sourcing the mount script ran `main`) and rewritten to `--source-only` with `declare -F` guards; the full-suite run then caught the missing `mount-loa.sh` download-list entry (#865) — fixed at `:88`. 8/8 now; `mount-loa-pipe-download-complete.bats` 3/3; the 129 mount/update/config/lint suites green; `lint-invariants.sh` 0 error; `repo-map-gen.sh --validate` consistent; `check-loa.sh` exits 0 and prints the skip line.
- **Docs**: CHANGELOG entry; `.loa.config.yaml.example:481-489` documents the key with the rationale; this repository sets it `false` explicitly (`.loa.config.yaml:585-593`).

Karpathy: 40-line lib, four inline guard lines in the scripts, one line per test suite, one job per workflow; no other abstraction. Fast-gate parity: `bash -n` on every touched script, both workflows parse with yq, YAML lint absent locally (noted).

Zero critical/high. The observations are residuals of the decision itself, tracked. Approval rationale: the AC rows hold with `file:line` evidence, the change is additive and fail-closed toward "off", the escape back to the old behaviour is one config line, and the dissent found nothing.

**Verdict:** APPROVED

---

## Observations

- **MEDIUM** (confidence: high) `.claude/aleph/**`, `.claude/skills/loa-aleph/**` (230 vendored files) — with the switch off nothing verifies these bytes: Loa's `.claude/checksums.json` never covered them (0 entries) and the Aleph verifier is now gated. They only execute on an explicit `/loa-aleph` invocation, but a tampered vendored launcher would pass every Loa gate. A consequence of the maintainer's decision, not of this diff's mechanics; the fix is to remove or quarantine the tree, or to bring it under Loa's own checksum. Bead bd-c7ma (maintainer decision).
- **LOW** (confidence: high) `.claude/scripts/lib/aleph-opt-in.sh:36-39` — the awk reader recognises exactly `aleph:` at column 0 followed by `enabled: true` as the next indented key under it; a YAML flow form (`aleph: {enabled: true}`) or a differently nested layout reads as disabled. Documented in the header and the example; acceptable for a boolean switch, but worth one sentence in the example (present).
- **LOW** (confidence: medium) `tests/unit/aleph-opt-in.bats:72-79` — AO-4 runs a nested `npx --no-install bats` on the ingestion suite (about a second); fine locally and in CI, noted for anyone profiling the unit job.

---

## Previous Feedback Status

First round for this bug sprint — no previous feedback.

---

## Acceptance Criteria Check

| Criterion | Status | Notes |
|-----------|--------|-------|
| Bug no longer reproducible (`Shell Tests` / `Verify install` cannot go red on Aleph bytes with the switch off) | Pass | suites skip (61 tests, 0 `not ok`, 20 skips in the ingestion suite); `verify` behind the gate; repo config `false` |
| Failing test proves the fix | Pass | AO-1..AO-7 + AO-5b, red→green recorded |
| No regressions | Pass | 129/129 related suites; full run 33 red = 38 baseline − 7 Aleph (skipped) + 2 caught-and-fixed (#865, AO-5); `lint-invariants` 0 error |
| Root cause, not symptom | Pass | no revert of the lint-required block; no Aleph-managed file edited; single predicate at every reach-in |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Fences and hooks untouched (`git diff -- .claude/hooks` empty)
- [x] Gate reads the base ref's config on pull requests (no self-flip)
- [x] No new dependency (POSIX awk); no network; no shell interpolation of config content
- [x] Aleph-managed files untouched; capabilities lint still authoritative

---

## Next Steps

1. `/audit-sprint sprint-bug-239` — writes the COMPLETED marker; `excluded_confirmed: 0`.
2. Push to PR #1266 and run Bridgebuilder.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":2},"excluded":0,"sprint_id":"sprint-bug-239","ts":"2026-09-22T11:00:00Z"} -->
