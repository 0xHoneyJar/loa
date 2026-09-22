# Review: fix(bug-725): handle ajv-cli@5+ in loa-doctor version probe

## Overall Assessment

Solid, well-scoped bug fix. `ajv --version 2>&1 | head -1` was capturing ajv-cli@5+'s
usage-error stderr text as if it were a version string; the fix replaces it with a
`_loa_probe_ajv_version()` helper that tries `--version` (v4 happy path), falls back to
parsing `--help` output (v5+), and finally falls back to a labeled placeholder. The pipefail
hazard in the fallback pipe (`grep` returns 1 on no match → `pipefail` propagates → `set -e`
would abort the caller before the placeholder is assigned) is explicitly called out in a
comment and correctly guarded with `|| true` at `head/.claude/scripts/loa-doctor.sh:252` and
`:256`. Test coverage is thorough: v4 path, v5+ with `--help` match, v5+ without a match
(placeholder), missing tool (positive control), two dedicated pipefail-abort regression
tests, and two source-level anti-regression greps against the legacy pattern reappearing.
Change is surgical — only the ajv probe is touched; `br`/`sqlite3` probes are left alone.

No blocking issues found. Approving with the following non-blocking concerns documented per
the adversarial review protocol.

## Adversarial Analysis

### Concerns Identified

1. **Untested against a real ajv-cli@5+ binary** — `head/tests/unit/bug-725-ajv-version-probe.bats:132-165`
   only exercises a hand-written bash stub whose `--help` output contains the literal
   string `ajv-cli version 5.6.0`. The regex at `head/.claude/scripts/loa-doctor.sh:254`
   (`grep -oE 'version [0-9]+\.[0-9]+(\.[0-9]+)?'`) assumes real ajv-cli's `--help` text
   uses that exact wording. If the actual installed binary phrases it differently (e.g.
   "Version:", different capitalization, or omits it from `--help` entirely), the fix
   silently degrades to the placeholder — the same class of "looks plausible but never
   verified against the real tool" gap the bug itself came from.
2. **Sibling probes carry the identical latent bug** — `br_ver` at
   `head/.claude/scripts/loa-doctor.sh:199` and `sqlite_ver` at `:208` still use the
   pre-fix `cmd --version 2>&1 | head -1 [...]` shape. If `br` or `sqlite3` ever emit a
   usage error on `--version` the same way ajv-cli@5 did, doctor output will misreport
   them the same way. Understandable to scope this PR to ajv only (that's what bug-725
   reported), but worth a follow-up ticket rather than leaving it implicit.
3. **`--version` happy-path regex rejects a `v`-prefixed version** — the check at
   `head/.claude/scripts/loa-doctor.sh:245` (`^[0-9]+\.[0-9]+`) requires the version string
   to start with a digit. A tool reporting `v4.11.0` (leading `v`) would fail this match
   and fall through to the `--help` parse unnecessarily — harmless functionally (the
   fallback still finds a version most of the time) but adds an avoidable extra process
   spawn and log surface for a plausible version format.
4. **Naming inconsistency** — every other helper in this file is prefixed `_doctor_*`
   (e.g. `_doctor_add_check`), but the new helper is `_loa_probe_ajv_version` at
   `head/.claude/scripts/loa-doctor.sh:228`. Minor, but it reads as a different
   subsystem's naming convention dropped into this file.

### Assumptions Challenged

- **Assumption**: ajv-cli@5+'s `--help` output reliably contains a literal
  `"... version X.Y.Z"` substring, in that exact word order, across ajv-cli 5.x/6.x
  releases (`head/.claude/scripts/loa-doctor.sh:234`, `:254`).
- **Risk if wrong**: Every ajv-cli@5+ install on a real machine silently reports
  `"unknown (ajv-cli@5+)"` even though a real version is available — degraded but not
  broken (no crash, no misleading garbage), so the blast radius is low, but the fix's
  core value proposition (surfacing the real version) quietly fails without any signal
  that the assumption broke.
- **Recommendation**: Non-blocking as-is, since the fallback degrades gracefully rather
  than reintroducing the original bug (garbage version text). Worth a follow-up to
  validate against a real `npm i -g ajv-cli@5` install once available in CI, or to note
  in the PR/commit that this was manually verified against a real binary.

### Alternatives Not Considered

- **Alternative**: Read the version out of `ajv-cli`'s installed `package.json`
  (e.g. `node -e "console.log(require('ajv-cli/package.json').version)"` resolved via
  `command -v ajv`'s directory, or `npm ls -g ajv-cli --depth=0 --json`) instead of
  parsing free-text `--help` output.
- **Tradeoff**: More robust to wording/format changes in `--help` text across ajv-cli
  releases, since `package.json` version is a structured, stable field. Costs: assumes a
  `node`/`npm` toolchain is present and discoverable, which the current shell-only
  approach doesn't require — `loa-doctor.sh` treats `ajv` as an arbitrary optional PATH
  tool and shouldn't assume it's a global npm install with a discoverable `package.json`.
- **Verdict**: Current text-parsing approach is justified — it keeps the probe
  dependency-free and consistent with how `br`/`sqlite3` are probed elsewhere in this
  file (`head/.claude/scripts/loa-doctor.sh:199`, `:208`). Not worth reconsidering for
  this fix.

## Previous Feedback Status

N/A — first review of this change; no prior `engineer-feedback.md` exists in this
PR-only review context.

## Next Steps

None required to merge. Optional follow-ups (non-blocking):
- File a tracking issue to apply the same `--version`-can-lie robustness treatment to
  the `br` and `sqlite3` probes if/when either tool changes its CLI shape.
- Confirm the `--help` regex against a real `ajv-cli@5`/`6` install when convenient.

All good (with noted concerns)

Concerns documented but non-blocking. See Adversarial Analysis above.

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":4},"sprint_id":"bug-725","ts":"2026-09-22T00:00:00Z"} -->
