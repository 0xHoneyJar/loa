# sprint-bug-268 Security Audit (round 1)

**Auditor:** Fable 5.1 lead (auditing-security contract; dissent via adversarial-review.sh --type audit)
**Date:** 2026-10-21T02:47:00Z
**Sprint Reference:** grimoires/loa/a2a/bug-20261021-7240bc/sprint.md (sprint-bug-268)
**Review:** grimoires/loa/a2a/bug-20261021-7240bc/engineer-feedback.md (All good, after round 1)
**Commits audited:** `c1477420` → `98b27811` → `40cfa761` on `fix/cycle-132-bugs` (diff vs `70330e48`: `evals/harness/seed-corpus-from-record.sh`, `evals/tests/seed-corpus.bats`; the eight labels files and `SHA256SUMS` are generated data)
**Dissent:** adversarial-audit.json (gpt-5.5-pro; status clean; 3 findings, 0 schema-rejected; 2 of ≤ 3 dissent runs used for this sprint)

---

## Scope

A generator that reads head files named by a TSV column and rewrites a tracked labels file. The audit read the new code for path containment, write atomicity and header injection.

## Findings

| Severity | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 1 |
| LOW | 2 |

### MEDIUM-1 — The labels `file` column reaches `open()` without containment (dissent DISS-C-001)
`evals/harness/seed-corpus-from-record.sh:349-366, 384-393` — `head(f)` builds `os.path.join(CORPUS, fx, "head", f)` from the TSV's `file` column; an absolute `f` discards the prefix and `..` segments walk out of the tree; the file is opened with `errors="replace"` so anything readable parses, and the sync then copies a line of that file into the labels as `must_match`. `build_manifest` has the same shape (`hp = os.path.join(CORPUS, fx, "head", r["file"])`), pre-existing. **Required:** one `head_path(fx, f)` helper used by both: reject an absolute path, any `..` component, a backslash or a NUL, and verify `os.path.realpath(result)` stays under `os.path.realpath(<corpus>/<fx>/head)`; refuse (exit 1, the row named) otherwise. Test: a labels row with `file: ../../etc/hostname` and one with an absolute path are refused by both `--build-manifest` and `--sync-labels`.

### LOW-1 — The final labels write is an in-place truncation (dissent DISS-C-002)
`:417` — `open(lpath, "w").write(new)` truncates before writing; an interrupt or a full disk leaves an empty or partial labels file. **Required:** write to a temp file beside it and `os.replace` (the convention every writer in this repository follows).

### LOW-2 — The approved_by guard misses Unicode line separators (dissent DISS-C-003)
`:340` — the guard rejects ASCII controls but `str.splitlines()` also breaks on U+0085, U+2028 and U+2029, so an `approved_by` carrying one of them passes the guard and re-parses as two lines. **Required:** reject any character for which `len(s.splitlines()) != 1` (and `\x7f`–`\x9f`), in the guard; test with U+2028.

## Secrets, zones, dependencies
- No credential handling; stdlib only; App Zone (`evals/`); `no-secrets.sh` passes over the labels; the tracked manifests untouched.

## Verdict

CHANGES REQUIRED — one MEDIUM (path containment on a file read that feeds a tracked artefact) and two LOW hardening items. The review's approval stands; this round is the audit's.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":0,"medium":1,"low":2},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-bug-268","ts":"2026-10-21T02:47:00Z"} -->
