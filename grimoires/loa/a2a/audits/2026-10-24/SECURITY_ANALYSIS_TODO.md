# Security analysis working file — cycle-133 Sprint 272 (global 272) audit, 2026-10-24

Scope: `git diff 8ef474af3 da2faa825` restricted to code (no `dist/`, fixtures, grimoires): the Bridgebuilder skill's `resources/` (paged fetch, enrichment guard, writer role, verdict table, entrypoint guard), `post-merge-orchestrator.sh` (candidate schema 2, ancestry gate, leased ledger fast-forward), `record-branch.sh` (new), `notes-guard.sh`, `pre-compact-marker.sh`, `security-audit-scope.sh`, `ledger-lib.sh`, `dec-write-lib.sh`, `tools/check-no-swallowed-jq.sh`, `tools/check-quarantine-expiry.sh` (new), `tools/check-knob-readers.sh`, `.github/workflows/{bats-tests,post-merge}.yml`, `.gitattributes`; plus the operational artefacts: the draft PR #1292, the landing commits, the DEC rows.

## Recon — untrusted sources (trust level)

| # | Source | Trust | Reaches |
|---|---|---|---|
| S1 | GitHub PR data via `gh api` (file names, statuses, patches, `changed_files`, base/head SHAs) | third-party author, UNTRUSTED | `paged-fetch.ts` (metadata map, selection, budget), `truncation.ts`, the posted coverage section (`safePath`), the marker JSON |
| S2 | writer model output (enrichment commentary) | UNTRUSTED model text | `enrichment-guard.ts` → posted commentary (after the guard) → `summarizeReviewVerdict` on the composed body |
| S3 | voice replies (consensus findings, verdict blocks) | UNTRUSTED model text, structured | `consensus-findings.ts` rendering (escaped), `review-verdict.ts` |
| S4 | the PR head's `.loa.config.yaml` | author-controlled under self-review | `config.ts` normal parse (`gh_max_buffer_bytes`, `max_files_per_pr`, `max_diff_bytes`); the TRUSTED view (base branch / `BRIDGEBUILDER_TRUSTED_CONFIG`) for `writer_role_allowlist`, `exit_on_degraded`, providers, aliases |
| S5 | `.run/post-merge-candidate.json` + `post-merge-ledger.patch` (artifact restored by the operator) | operator-inspected; integrity via sha256 and byte-equal re-canonicalisation | `post-merge-orchestrator.sh --publish` (tag, release, ledger push, notify) |
| S6 | the ledger patch | validated | `validate_ledger_patch` → `build_ledger_commit` (temp index) → `ledger_transition_ok` |
| S7 | record paths (ledger-derived a2a/reports/bug dirs, `--manifest`, `--add`), the final tree's symlinks and bytes | agent-written files, UNTRUSTED text; public once pushed | `record-branch.sh` collect → scan (`cmd_credscan`) → temp index → `commit-tree` → `update-ref` |
| S8 | `tests/QUARANTINE.tsv` rows | repo-tracked, reviewed | `check-quarantine-expiry.sh` (`$REPO/$tfile` read-only existence/grep; `br show <bead>` with a regex-validated id) |
| S9 | the TAP file (`tee` of bats) | CI-generated | the totals step (`grep -Ec`, refuses zero lines) |
| S10 | `br show --json` output | tool output | `jq` parse (stdout only; stderr apart; `</dev/null`) |
| S11 | `.run/state.json`, `.run/simstim-state.json` | state zone | `pre-compact-marker.sh` (`jq -r` reads; liveness) |
| S12 | NOTES.md content | agent prose | `notes-guard.sh build_retained` (section ranges by heading; awk byte budget) |

## Recon — dangerous sinks

| # | Sink | Guard |
|---|---|---|
| K1 | GitHub comments posted by Bridgebuilder (coverage section, consensus block, commentary) | `safePath` (backtick/newline/`<`/`>`), rendered JSON escapes `<`, `>`, backticks; the marker escapes `--`; the commentary only after the guard; the block is always the pipeline's own |
| K2 | the merge verdict (`REQUEST_CHANGES` / `COMMENT` / `UNKNOWN`) | decision table: blocking findings first; every degradation → UNKNOWN + merge blocked; a block verdict can never auto-APPROVE |
| K3 | the writer dispatch (a model that could act) | `effectiveWriterAllowlist` = trusted config ∩ frozen `PROVEN_WRITER_STANCES`; `codex-headless` refused; stance keyed by dispatched model, voided on provider mismatch; `toolCallsAttempted > 0` → ineligible |
| K4 | `git push` of a tag / the ledger fast-forward to `main`; `gh release create`; PR comment | candidate digest + byte-equal JCS; checkout binding; fresh-fetch ancestry at preflight and per step; identity-matched tag; `--force-with-lease=refs/heads/main:<observed>` with `<observed>` from the same step; deferral file on any other `main`; ICE forbids force-push elsewhere |
| K5 | `update-ref` of the public record branch | parents on origin; CAS with the observed old value; every refusal before `commit-tree`; `--dry-run` writes nothing |
| K6 | the record tree contents (public) | escape and symlink validation before staging; nested `.git`/gitlinks refused; full-tree credential scan (eight never-bypassable classes + placeholder filter); hits print `path:line:class` |
| K7 | file writes by the validator / CI steps | `$RUNNER_TEMP`, `mktemp` with `trap`; the manifest under `grimoires/loa/a2a/record-manifests/<cycle id>/<slug>.json` (cycle numeric, slug `[a-z0-9-]`, ≤ 80 chars) |
| K8 | `br show "$bead"` subprocess | `^bd-[a-z0-9]+$` before use; `</dev/null`; stdout/stderr apart |
| K9 | `bats-tests.yml` steps | `set -o pipefail` in the unit step; totals step exits non-zero on a validator failure other than 3; the quarantine gate distinguishes 1/2/3 |
| K10 | `main.ts` on import | `isEntrypoint(realpath)` guard; a bare import spawns nothing (subprocess test with a fake `gh`) |

## Investigate pass — results

- S1→K1: file names reach a markdown list inside inline code after `safePath`; a name with a backtick becomes `'`; `<`/`>` percent-encoded; newlines replaced — a name cannot break out of the code span or inject HTML. The marker is an HTML comment whose payload escapes `--` inside strings so a name cannot close it. OK.
- S1→K2: `unknown_omitted` floored at 0; a `changed_files` above the endpoint cap sets `files_list_truncated`; any reviewable omission or unknown file blocks; `no_patch` counts as reviewable, so a text file whose patch GitHub withheld blocks rather than slipping through; `excluded_loa`/`excluded_pattern` do not block (by design), `excluded_fail_closed` does. OK.
- S2→K1/K2: the guard runs before the commentary is posted; the composed body is re-summarised, so a second block smuggled into commentary is `verdict_conflict`; unmarked findings JSON rejected; a faithful echo is stripped. Residual (LOW, review observation): a tool tag mid-line outside code spans passes the grammar check; an unclosed fence masks the remainder and, when rendered, swallows the coverage section. Beads bd-t2gqd.
- S4→K3: `writer_role_allowlist` and `exit_on_degraded` come from the TRUSTED view only (`TRUSTED_VIEW_YQ`); `gh_max_buffer_bytes` from the normal parse, bounded 1–512 MiB — a PR head can raise the per-call buffer to 512 MiB (memory pressure on the reviewer's host), never the verdict. LOW, accepted (documented as memory-only in the example config).
- S5/S6→K4: the ledger patch is one text diff of one path with an exact `active → archived` transition; `apply --cached` into a temporary index so the checkout is never touched; the commit identity and dates are pinned and the rebuilt id must equal the sealed `new`; ancestry is re-verified before each remote write; the lease value is the one observed in that step. The `--allow-v1 REASON` path skips the ancestry gate by design (recorded, runbook). OK.
- S7→K5/K6: paths through a symlinked directory, absolute or escaping targets, unrecorded targets, gitlinks and nested repositories are refused before `add -f`; the scan runs over the complete exported final tree (bounded 4 GiB); the eight classes cannot be bypassed and the placeholder filter needs ≥ 6 distinct bytes (+ digit and letter for generic shapes). Residual (MEDIUM, review observation, bead bd-tg7zk): no generic assignment class (`api_key = …`, `token: …`), no JWT or `ya29.` class — the lead's `detect-secrets` pass covered this branch. OK for the sprint; hardening follows in Sprint 3's lib extraction.
- S8/S10→K8: bead ids regex-validated; `$REPO/$tfile` is only tested with `[[ -f ]]` and `grep -F`; a `..` path reads a tracked repo file at worst (no write). `br` cannot consume the row loop's stdin. OK.
- S9→K9: zero TAP lines → `die2` (exit 2) → the totals step exits 2 (not 0/3). OK.
- S11: `jq -r` reads with string comparisons; an unparseable file is silent; a bad window falls back to 7 days. OK.
- S12: section detection by heading at line start; a fenced `## Blockers` inside the Session Log would be read as a heading (pre-existing behaviour of `index_blocks`; the retained file is still valid markdown and the archive holds everything). LOW, informational.
- K10: `isEntrypoint` compares `realpath(import.meta.url)` with `realpath(argv[1])`; an unresolvable `argv[1]` is "not the entrypoint" (fail-safe); `entry.sh` runs `node dist/main.js` directly. OK.
- CI: `post-merge.yml` lists `post-merge-ledger.patch` in both artifact uploads with `if-no-files-found: error`; `actions/upload-artifact@v4` applies that option only when the search across all patterns finds no file, so a non-cycle merge (no ledger patch) still uploads the other four files. If a future action version changes that, the failure is a visible red retain step, never a silent publish.
- Secrets in the branch: `detect-secrets` over every changed file — hex strings in `checksums.json`/`.map`, the `api_key_mode` keyword, `fixture-not-a-key`, a PEM header in a comment, pre-existing CHANGELOG lines; nothing live. The PR #1289 fixtures are verbatim public threads.
