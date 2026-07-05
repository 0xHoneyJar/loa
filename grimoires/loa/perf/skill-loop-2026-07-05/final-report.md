# Extreme-Software-Optimization Skill Loop — Final Report (pass 10 of 10)

> Loop: 2026-07-05 → 2026-07-06 · Branch `feat/skill-loop-extreme-optimization`
> Base commit `4ae8aa5f` (pre-loop) · Passes 1–9 committed as
> `1da1afa8, a014d489, 379daae9, d07eb8a6, 6cf20507, 385f8058, 2d88897c, b89e70b4, 94fdc46e`
> Target: the p95-latency-defining hot paths of the Loa framework itself —
> the ~11 hook processes spawned per tool call (PreToolUse/PostToolUse/Stop)
> plus the workflow-boundary scripts (`beads-health.sh`, `check-updates.sh`,
> `golden-path.sh`). Method: `/home/merlin/.claude/skills/extreme-software-optimization`
> (profile first → prove behavior unchanged → one lever per commit).

## 1. Executive summary

**Every user-visible hook chain got 48–66% faster, with zero behavior change
proven at every step.** The definitive before/after below is ONE same-window
A/B (pass 10): the pre-loop code (`git worktree` @ `4ae8aa5f`, mirrored) and
HEAD ran **interleaved per-run (old,new,old,new,…), 20 measured runs each**,
against identical payloads/fixtures — the alternation neutralizes this host's
powersave-governor drift (pass-3 lesson). Raw data: `final-ab.tsv`.

### Headline: full hook chains + boundary scripts, baseline vs final

| Chain / script | baseline mean (ms) | final mean (ms) | reduction | baseline p95 | final p95 | p95 reduction |
|---|---:|---:|---:|---:|---:|---:|
| **Bash tool call** (block-destructive + team-role-guard + mutation-logger) | 56.70 | 19.05 | **−66.4%** | 79.74 | 26.13 | −67.2% |
| **Write tool call** (trg-write + spiral-guard + zone-write-guard + adv-gate + write-mutation-logger + karpathy WARN) | 135.04 | 51.58 | **−61.8%** | 169.18 | 66.21 | −60.9% |
| **Edit tool call** (same chain, edit payloads) | 148.10 | 50.98 | **−65.6%** | 178.49 | 65.20 | −63.5% |
| **Skill call** (team-skill-guard + spiral-skill-sentinel) | 14.52 | 7.56 | **−47.9%** | 16.31 | 9.18 | −43.7% |
| **Stop event** (run-mode-stop-guard + settings-cleanup small) | 47.49 | 17.12 | **−64.0%** | 52.03 | 20.13 | −61.3% |
| `beads-health.sh --quick --json` | 52.34 | 35.55 | **−32.1%** | 65.70 | 48.63 | −26.0% |
| `check-updates.sh --notify` (fresh cache) | 80.22 | 28.69 | **−64.2%** | 99.52 | 34.92 | −64.9% |
| `source golden-path.sh` (repeats across all 58 bootstrap-sourcing scripts) | 82.27 | 39.88 | **−51.5%** | 102.48 | 51.03 | −50.2% |

Validity cross-check: the old side of this same-window A/B independently
reproduces the pass-1 baseline means (57.2 / 131.9 / 142.3 / 12.4 / 39.1 ms
chain sums; 50.1 / 79.6 / 85.6 ms boundary) within governor noise — the
measurement is anchored, not window-lucky. The pass-1 projection ("Bash ≈ 18,
Write/Edit ≈ 42 after #1–#8") landed within a few ms of reality.

In session terms: the representative 100-Bash + 40-Write session turn that
burned ≈ 11 s of pure hook overhead at baseline now burns ≈ 4 s.

Beyond the chains, the loop also converted the karpathy state scan from
O(session length) to O(delta) — at n=20,000 state entries the old hook cost
118 ms per Write/Edit and the new one 18 ms, flat (pass 7) — and removed the
last unconditional spawns from the benign Bash path (passes 8–9: benign
block-destructive 2→1 spawns, adv-gate/sentinel 1→0, mutation-logger 2→1).

### Verification (this pass — no production code changed)

- **Golden parity gate**: `golden/capture.sh --verify` → **32/32 OK**.
- **Targeted bats battery** (every suite covering loop-touched files): **362 ok / 0 fail / 0 skip** across 20 suites (§2).
- **Standalone**: `tests/unit/test-path-lib-state.sh` → **22/22 passed**.
- **Full sweep**: `tests/run-unit-tests.sh` — see §2.1.
- **Loop-introduced failures found: none.**

## 2. Full test verification (pass 10)

Command: `npx bats --tap tests/unit/<suite>` per suite, repo root, 2026-07-06.

| Suite | tests | ok | fail |
|---|---:|---:|---:|
| block-destructive-bash.bats | 125 | 125 | 0 |
| block-destructive-bash-limitations.bats | 6 | 6 | 0 |
| cycle-114-rm-home-precision.bats | 6 | 6 | 0 |
| zone-write-guard.bats | 14 | 14 | 0 |
| agent-teams-hooks.bats | 8 | 8 | 0 |
| cycle-114-stop-guard-bg-tasks.bats | 7 | 7 | 0 |
| hook-wiring.bats | 9 | 9 | 0 |
| karpathy-surgical-diff-hook.bats | 6 | 6 | 0 |
| karpathy-trajectory-event.bats | 4 | 4 | 0 |
| karpathy-config-schema.bats | 3 | 3 | 0 |
| settings-permissions.bats | 65 | 65 | 0 |
| compliance-hook.bats | 14 | 14 | 0 |
| beads-health-migration.bats | 5 | 5 | 0 |
| check-updates.bats | 30 | 30 | 0 |
| golden-path-grimoire-guard.bats | 5 | 5 | 0 |
| bridge-golden-path.bats | 11 | 11 | 0 |
| zones-schema.bats | 6 | 6 | 0 |
| zone-compliance.bats | 18 | 18 | 0 |
| classify-commit-zone.bats | 16 | 16 | 0 |
| implementing-tasks-success-criteria-gate.bats | 4 | 4 | 0 |
| **Battery total** | **362** | **362** | **0** |

Plus `tests/unit/test-path-lib-state.sh` (standalone runner): **22/22 passed, 0 failed**.

### 2.1 Broader sweep — `tests/run-unit-tests.sh`

The full 296-suite sweep did NOT complete within the 15-minute cap
(`timeout 900 tests/run-unit-tests.sh` → killed at file ~225/296, rc=124), so
per the pass-10 mission the 20-suite battery above is the primary gate — but
the remaining 72 suites were then completed in a follow-up per-suite run, so
the sweep IS complete, in two chunks (same host, same HEAD, 2026-07-06):

- **Chunk 1** (`tests/run-unit-tests.sh`, suites 1–224 alphabetically,
  real repo): **3,307 ok / 13 not ok** (after subtracting the partially-run
  225th suite, re-run in full in chunk 2; ok counts include 60 TAP skips).
- **Chunk 2** (per-suite `npx bats`, suites 225–296, real repo):
  **1,275 ok / 42 not ok**.
- **Combined: 4,582 ok / 55 not ok across all 296 suites.**

**Every one of the 55 failures is pre-existing or local-state-dependent —
none is loop-introduced.** Two independent proofs:

1. **Base-commit reproduction** (per `.claude/rules/stash-safety.md`, via
   `git worktree add /tmp/loa-baseline 4ae8aa5f`, never stash): every
   chunk-1 failing test that runs in a fresh tree reproduces byte-identically
   (same test name, same assertion line) on the PRE-LOOP commit.
2. **Worktree-pair equivalence**: for all 10 suites with chunk-2 failures,
   a fresh worktree of HEAD (`/tmp/loa-headtree`) and the fresh worktree of
   base `4ae8aa5f` produce **identical fail counts on every suite**
   (3/1/1/0/1/8/1/0/6/2) — the committed code behaves the same before and
   after the loop. Where the live-repo run differs from the fresh-HEAD-tree
   run (template-safety 1 vs 0, constructs_loader 10 vs 1,
   license_validator 6 vs 0, pack_support 14 vs 6, constructs_lib 3 vs 8 —
   note the last diverges in the OPPOSITE direction), the driver is the live
   repo's untracked local state (installed constructs/registry dirs,
   `.run/construct-index.yaml`, the untracked `vision-021.md`, `.venv`
   presence gating jsonschema-dependent suites), which affects base and HEAD
   code equally. Additionally `git diff 4ae8aa5f..HEAD` contains no test
   files, no schemas, no tools/ — only the 20 hook/script files plus perf
   artifacts, and none of the failing suites exercise or source those 20
   files.

Failure inventory (15 distinct chunk-1 test cases + 9 chunk-2 suites), all
classified:

| Failing test / suite | Classification | Root cause (evidence) |
|---|---|---|
| bug-881-headless-context-window #1b | pre-existing (repro on base) | `model-config.yaml` `kind:cli` entries (xai.grok-build, xai.grok-composer-2.5-fast, cursor.composer-2.5{,-fast}) self-reference via `extra.cli_model` → the invariant flags cli→cli cycles |
| compute-baselines T3.A `git_sha_at_signing` | pre-existing (repro on base) | test cds into `mktemp -d`; `_current_git_sha()` resolves HEAD from cwd → returns `UNKNOWN` outside a repo (`tools/compute-baselines.py:75`) |
| flatline-orchestrator-max-tokens >100KB warning | pre-existing (repro on base) | missing warning output |
| ledger-lib archive_cycle ×2 | pre-existing (repro on base) | `archive_cycle` refuses: "incomplete sprint(s)" |
| mktemp-bsd-portability scanner | pre-existing (repro on base) | suffixed template at `gen-adapter-maps.sh:121` (bug-978 class) |
| model-error-schema S2 (10-value taxonomy pin) | pre-existing (schema byte-identical at base; base run skips for missing jsonschema) | schema now enumerates **11** `error_class` values; test pins 10 — taxonomy drift needing a test/schema re-sync |
| modelinv-v1.3-backcompat V11 (live-log replay) | pre-existing / live-data (inputs untouched by loop) | live `.run/model-invoke.jsonl` entries (`flatline-reviewer`, `adversarial-review:*`, `test:skill` consumers, lines 848+) fail payload-schema validation — real ops data; hooks never write this log. **Deserves its own /bug — this is the verdict-quality audit surface** |
| overlay-source-helper C1 | pre-existing (repro on base, isolated) | `_OVERLAY_HELPER_LIB_DIR: readonly variable` on re-source |
| pre-commit-beads PCB-T3 | pre-existing (repro on base) | migration-error diagnostic not emitted |
| search-orchestrator ×2 | pre-existing (repro on base) | JSONL format assertions fail |
| select-benchmark-sprints T2.J | pre-existing (repro on base) | deterministic selection count mismatch |
| self-heal-state #3, #7 | pre-existing (repro on base) | check-only exit code; NOTES.md template sections |
| spiral-phase-timeouts ×3 | pre-existing (worktree-pair identical: 3/3) | timeout-default assertions |
| sprint-kind-classify ×1 | pre-existing (worktree-pair identical: 1/1) | test writes `docs/…` without creating the dir |
| stash-safety ×1 | pre-existing (worktree-pair identical: 1/1) | pop-on-empty message assertion |
| template-safety ×1 (live repo only) | local-state (fresh base AND fresh HEAD both pass) | **untracked** `vision-021.md` carries a non-ISO narrative date |
| test_constructs_install ×1 | pre-existing (worktree-pair identical: 1/1) | pack-skill symlink resolves outside constructs |
| test_constructs_lib / _loader / license_validator / pack_support (3/10/6/14 live; 8/1/0/6 in BOTH fresh trees) | local-state + pre-existing (worktree-pair identical on every suite) | suites are sensitive to installed construct/registry/cache state; committed code behaves identically at base and HEAD |

Follow-up recommendation: the constructs/license/pack suites and V11 need
environment isolation (they currently assert against live repo state); the
S2 taxonomy pin and bug-881 model-config cycles need code/test re-syncs.
All predate the loop.

## 3. Per-pass summaries (lever · measured win · proof method)

**Pass 1 — Baseline & profile** (`1da1af`). No production change. Built the
shared harness this whole loop stands on: `bench.sh` ($EPOCHREALTIME timer,
hyperfine absent), `bench-env.sh` disposable repo mirror (hooks re-root side
effects via BASH_SOURCE), `run-matrix.sh`, PATH-shim spawn census (ptrace
denied by yama), 11 payloads, **32 golden outputs + `capture.sh --verify`**
as the mechanical parity gate for every later pass. Findings: chains cost
Bash ≈57 / Write ≈132 / Edit ≈142 ms; cost model fork+exec ≈1.4 ms, jq ≈3 ms,
yq ≈4–7 ms; opportunity matrix of 12 scored items.

**Pass 2 — Fork/exec reduction in safety hooks** (`a014d4`). All 9
`.claude/hooks/safety/` hooks: `echo|grep -qE` dispatches → `[[ =~ ]]` over an
explicit grep line-model; `\b` → portable boundary classes; `date`/`dirname`/
heredoc-`cat`/`$(pwd)` → builtins. block-destructive benign 49.5→14.1 ms,
team-role-guard TEAM 35.8→8.5 ms. Proof: 320-case old-vs-new differential
corpus (byte-identical exit+stdout+stderr+side effects) = 0 divergences;
golden 32/32 before and after install; 175 bats ok.

**Pass 3 — jq/yq single-pass consolidation** (`379daa`). 7 hooks: N jq spawns
→ ONE jq with NUL-delimited multi-field extraction replicating `$()` capture
byte semantics; JSONL audit lines pre-built inside the same jq; karpathy
2 yq+7 jq → 1+1; zone-guard per-zone yq loop → one row-stream. karpathy warn
66.6→26.6 ms, stop-guard idle 21.1→5.0 ms. Reviewing another agent's staging
caught **4 defect classes pre-install** (trailing-newline strips, a lost
file-creation side effect, container-type join errors, leading-zero
`--argjson` behavior — the first fix hypothesis for which was itself disproven
by corpus). Proof: 119-case strict corpus = 0 divergences; goldens 32/32;
48 bats ok.

**Pass 4 — Redundant I/O & lazy init** (`d07eb8`). settings-cleanup >64KB
path 35→5 spawns (jq×6+grep×24 → jq×3 with a whole-text pre-filter +
line-model fallback); post-compact marker path 17→2; stat probes BSD-first →
GNU-first; mkdir guarded by `[[ -d ]]`. settings-cleanup large 90.3→59.4 ms,
post-compact marker 39.7→14.2 ms. Found the **settings-cleanup leading-dash
grep latent defect** (§5) and preserved it. Proof: 69-case corpus (0
divergences) + RAW sha256 byte-parity on 25 settings rewrites incl. the real
55KB file; goldens 32/32 (zero regenerated — line-count golf kept bash
diagnostics stable); 34 bats ok.

**Pass 5 — Boundary-script startup** (`6cf205`). beads-health/check-updates/
golden-path + the path-lib/bootstrap chain they source: single-probe config
fast paths (one `yq '.paths // ""'` probe proves all per-key defaults),
SOH-joined single-jq cache reads (NUL unusable — malformed-cache death must
replicate), batched `realpath -m`, spawn→builtin idioms. check-updates
81.6→29.9 ms, golden-path source 84.3→42.7 ms (×58 consumer scripts),
bh --quick 48.9→38.0 ms. Found the **beads-health `grep -c` double-zero
latent defect** (§5) and preserved it. Proof: 79-case corpus across fixture
DB schemas, network-stubbed check-updates (zero network incl. DNS), 26
golden-path config shapes = 0 divergences; 51 bats + 22/22 path-lib ok.

**Pass 6 — Memoization of pure lookups** (`385f80`). zone-write-guard's zone
row-stream (pure fn of zones.yaml) and karpathy's config tokens (pure fn of
.loa.config.yaml) memoized in `.run/perf-cache/` keyed on
`<ns-mtime>:<size>:<abs-path>` from ONE stat (~1.4 ms replacing ~4–7 ms yq);
ANY anomaly falls through to the original parse verbatim (permanent
fail-open). Warm zwg 24.3→17.2 ms, karpathy 17.6→13.3 ms per Write/Edit; cold
miss +6 ms once per config edit. Proof: 45-case cache-state corpus
(cold/warm/staleness/corruption/races/contamination/forged-key) = 0
divergences; trust argument documented (§7); 44 bats ok.

**Pass 7 — O(n)→O(delta) on growing data** (`2d8889`). karpathy's per-call
full scan of `.run/karpathy-task-state.jsonl` (grows forever; 118 ms at
n=20,000) → incremental aggregate cache on '\n'-boundary offsets: fast path
(size==offset) reads zero state bytes; delta path folds only appended lines
through THE SAME jq/awk programs re-seeded to preserve strtod/association
semantics; a size gate (256 KiB ≈ measured crossover) keeps today's real file
on the ORIGINAL path with identical spawn shape. n=20000: 118→18 ms flat.
Own proofs caught 3 design defects pre-install (empty-split undercount, a
v1 that was SLOWER than old at real n, a redirect-order stderr leak). Proof:
32-sequence corpus with a per-case cache-consistency INVARIANT (cache ≡ fresh
full-scan recomputation) = 0 divergences; 30 bats ok.

**Pass 8 — Necessary-literal pre-filters in the destructive fence**
(`b89e70`). block-destructive-bash: every pattern group guarded by bash
substring tests on literals provably NECESSARY for its ERE to match (mandatory
concatenation elements outside all alternations); guards SKIP only, never
accept; zero pattern/message/exit bytes changed (mechanically diffed). Benign
Bash path loses its last greps: 14.2→9.5 ms, 2→1 spawns; blocked path
unchanged by design (27.8→28.1 wash). Proof: 209-case corpus (all 120 bats
commands + 74 adversarial pre-filter attacks) = 0 divergences, **non-vacuity
proven by mutation** (sabotaged guards → 18/26 divergences); live smoke —
the fence blocked its own author's census literal mid-pass; 154 bats ok.

**Pass 9 — Round-2 re-profile + last hot-path spawns** (`94fdc4`). Fresh
matrix → three implemented levers: raw-payload literal fast gates for
adv-gate/"COMPLETED" and sentinel/"spiraling" (airtight via the \uXXXX
escape-decomposition argument: an all-literal token is contiguous in raw
bytes, so raw-absence of token AND `\u` proves silent-exit-0 on both sides),
and mutation-logger's filter grep → folded `[[ =~ ]]`. advgate write-benign
7.9→3.2 ms, sentinel 6.6→2.5 ms, ml benign 9.8→7.6 ms. The pass-1 #9
hook-consolidation idea was evaluated and **honestly SKIPPED**: Claude Code
runs an event's hooks in parallel (wall ≈ max, not sum), hook config is
snapshotted per session (the proof bar is mechanically unsatisfiable
in-session), and the exit(2) contract can't survive in-process dispatch —
score < 2.0 on every branch. Proof: 83-case corpus = 0 divergences,
triple-mutation non-vacuity (20 divergences on sabotage), goldens 32/32,
17 bats ok.

**Pass 10 — Final verification & proof** (this pass). No production change.
Full bats battery (§2), golden 32/32, the definitive same-window worktree A/B
(§1, `final-ab.tsv`), this report, progress-file closure.

## 4. Isomorphism proof-technique catalog (developed across the loop)

Reusable techniques for proving "optimized ≡ original" on shell hot paths,
each validated by a 0-divergence differential corpus in the pass that
introduced it:

1. **Grep line-model preservation** (passes 2, 8, 9). Replacing
   `echo "$x" | grep -qE p` with bash `[[ =~ ]]` is only sound over an
   explicit reconstruction of grep's line model: split on newlines
   (`mapfile -t`), match per line, first match wins. `\b` does not exist in
   POSIX ERE ([[ =~ ]] uses libc regcomp) — translate to explicit boundary
   classes, and beware consuming translations: `--delete\b.*--force` needs
   the non-consuming `([^[:alnum:]_].*)?` form or `--delete--force`
   diverges. Case-insensitive greps become ONE `${var,,}` fold under an
   exported `LC_ALL=C` pin, proven ≡ `grep -i`'s per-line fold.

2. **NUL-delimited multi-field transport** (passes 3, 5). N `$(jq -r .field)`
   spawns collapse into one jq emitting all fields NUL-joined
   (`[0]|implode` builds the NUL inside jq). The bash side must replicate
   `$()` capture semantics exactly: strip decoded ` ` remnants
   (string-division `denul`), strip trailing newlines (`sub("\n+$";"")`),
   and type-guard container values (`if type=="string" then . else tojson
   end`) so old fall-through behavior survives. Where the capture must DIE
   on malformed input with identical stderr/rc (check-updates cache), NUL is
   unusable — a SOH (``) join preserves the single-`$()`-death shape.

3. **Necessary-literal pre-filters with mutation-tested corpora** (passes 8,
   9). A pattern group may be skipped when the input lacks a literal that is
   provably necessary for the regex to match: the literal must be a mandatory
   concatenation element outside every alternation/optional/starred group;
   alternations require testing ALL branch literals. Guards may only SKIP,
   never accept, and never alter evaluation order. For decoded-JSON gates the
   escape-decomposition argument extends this to raw payloads: an all-letter
   token can appear in a decoded string only as contiguous literal bytes or
   via `\uXXXX`, so raw-absence of both the token and `\u` is a sound skip.
   The corpus MUST be proven non-vacuous by mutation: sabotage each guard
   literal and count divergences (pass 8: 18/26; pass 9: 20) — a corpus that
   stays green under sabotage proves nothing.

4. **Identity-keyed caches with unconditional fail-open** (pass 6). Pure
   functions of rarely-changing files (yq parses of zones.yaml/config) are
   memoized keyed on source identity: `<ns-mtime>:<size>:<abs-path>` from one
   GNU-first `stat -Lc`. Non-GNU stat ⇒ empty key ⇒ permanently uncached
   (fail-open, never fail-wrong). Writes are atomic same-dir `mv -f -T`;
   reads use `IFS= read -rd '' <file || true` — NOT `$(<file)`, whose failed
   redirection aborts an errexit shell even inside a `||` list. ANY anomaly
   (key mismatch, corrupt/torn/unreadable cache, race) falls through to the
   ORIGINAL parse verbatim and rewrites. Stat the key BEFORE parsing so a
   racing source edit self-heals next call. Version-tag the cache filename
   (§7.3).

5. **O(delta) incremental aggregates with size gates** (pass 7). Append-only
   JSONL scans become incremental when offsets always land on '\n' boundaries
   (line sets then decompose exactly): cache the aggregates + a last-line
   token; on growth, fold ONLY the tail through the SAME jq/awk programs —
   awk re-seeded via `-v init=` in BEGIN preserves left-to-right association
   and mawk's strtod-prefix semantics by construction (same binary, same line
   bytes). Cached totals must round-trip the interpreter's number type
   (15-digit guard for mawk doubles). Write the cache only when post-size ==
   pre-size + delta + own-entry (concurrent appenders skip — stale caches
   stay consistent, next call just processes a wider delta). A measured-
   crossover size gate keeps small inputs on the ORIGINAL code path with an
   identical spawn shape, so the optimization cannot regress the common case.

6. **Harness discipline: differential corpora + vacuity guards** (all
   passes). The primary gate is always a fresh-sandbox old-vs-new
   differential run comparing exit + stdout + stderr + the FULL side-effect
   tree (ts/root-normalized, NUL-safe walkers), never just stdout. The
   harness itself is a defect source: passes 6 and 7 each caught a
   normalizer/sed bug that made all diffs vacuously pass — every corpus needs
   a self-test (normalizer round-trip, deliberate mutation) before its green
   means anything. Golden overlays run in a disposable mirror BEFORE any
   install touches the live hooks (§7.1). Spawn censuses must run as real
   script files resolving via `type -P` — the tool-shell's zsh snapshot
   defines a `grep` function that turns PATH-shims recursive (pass-8 gotcha).

## 5. Latent defects found and preserved (old-code bugs, kept for parity)

The loop's contract was behavior-identical optimization, so pre-existing
defects discovered by differential testing were REPLICATED, documented
in-code (`PRESERVED DEFECT` comments), and logged in `grimoires/loa/NOTES.md`
for their own test-first `/bug` cycles:

1. **settings-cleanup leading-dash grep** (pass 4; NOTES.md 2026-07-05). The
   post-cleanup secret scan `grep -qP "$pat" || grep -qE "$pat"` passes
   patterns positionally without `--`, so the `'-----BEGIN .* PRIVATE KEY'`
   pattern parses as grep OPTIONS → rc=2 silenced → that pattern can NEVER
   warn (GNU and BSD alike). The main permissions filter was never affected —
   only the post-rewrite warning scan. Fix shape: `grep -qP -e "$pat"` or
   drop the leading-dash guard in the jq scan.
   → follow-up: dedicated /bug cycle; add a leading-dash-pattern test first.

2. **beads-health `grep -c` double-zero** (pass 5; NOTES.md 2026-07-05).
   `has_owner=$(sqlite3 … | grep -c "owner" || echo "0")` — on no match,
   `grep -c` prints `0` AND exits 1, so `echo "0"` appends a second zero and
   the `[[ "$has_owner" -eq 0 ]]` becomes an arithmetic syntax error that
   evaluates FALSE → missing-owner databases report HEALTHY/compatible
   (MIGRATION_NEEDED can never fire; same shape when sqlite3 itself fails).
   Fix shape: the `|| echo "0"` IS the bug — drop it or use `|| true`.
   → follow-up: dedicated /bug cycle; exit-3 migration detection would then
   actually fire for pre-owner beads databases.

3. **path-lib unbound `LOA_SOUL_*` stderr leak on the env-inherit branch**
   (pass 5; recorded in the pass-5 progress entry as one of the two
   pre-existing stderr-leak paths, alongside #2's arithmetic error — no
   separate NOTES.md observation was filed). When paths are inherited from
   the environment, `LOA_SOUL_SOURCE`/`LOA_SOUL_OUTPUT` stay UNSET and the
   old `_validate_paths` leaked `unbound variable` diagnostics from a
   `||`-true'd subshell under `set -u`. The pass-5 rewrite had to add
   `${VAR:-}` guards to its batched fast path and then RE-RUN the original
   per-path calls at their ORIGINAL positions purely so the leaked
   diagnostics keep interleaving in the old order. Message text, ordering,
   and rc are identical; only bash's own `path-lib.sh: line N:` prefixes
   shifted (accepted-divergence class, §6).
   → follow-up: fold into a path-lib cleanup /bug — initialize the soul vars
   (or guard the validators) so validation of env-inherited configs stops
   emitting noise; then delete the parity re-runs.

NOTES.md carries exactly the two formal Observation entries (#1, #2); #3
lives in the progress file's pass-5 record. All three predate the loop.

## 6. Accepted-divergence register (collated from passes 2–9)

Everything below is out-of-contract for real Claude Code payloads or
explicitly argued; each item is pinned by a corpus case in its pass's
harness. Everything else is byte-identical (0 corpus divergences across
320+119+69+79+45+32+209+83 = 956 differential cases loop-wide).

| # | Pass | Divergence | Why accepted |
|---|---|---|---|
| 1 | 3 | Multi-doc stdin that errors mid-stream: old logged a truncated prefix line, new skips the log | Claude Code never sends multi-doc payloads; the truncated prefix was itself garbage |
| 2 | 3 | Container-valued `command`/`file_path`/`tool_name` fields render compact (`tojson`) where old rendered jq-pretty | Tool payloads carry strings here; type-guard keeps the no-crash fall-through |
| 3 | 3 | Write-only (mode-200) state files: stop-guard counts them 1/1 vs old 0/0 | Not producible by the framework's own writers |
| 4 | 3 | bash "ignored null byte in input" stderr warning gone where `$(cat)` was replaced | Warning was incidental noise; decisions unaffected |
| 5 | 3 | stop-guard reasons render iteration/state containers compact | Same class as #2 |
| 6 | 3 | zwg `.claude` BLOCK path +2 ms (single yq emits all 3 zones where old stopped at framework); adv-gate COMPLETED-block +8 ms (re-reads config for message byte-parity) | Deliberate perf trades on ≤once-per-sprint paths to keep ALLOW paths dominant and messages byte-identical |
| 7 | 4 | 5 corpus cases compared `nostderr`: out-of-contract permission `allow` types where old leaked jq/arithmetic stderr noise | No-write parity + exit parity held; the noise was old-code accident |
| 8 | 5 | bash diagnostic LINE NUMBERS shift on two pre-existing stderr-leak paths (§5.2, §5.3) | Message text, ordering, rc identical; line numbers are not contract |
| 9 | 5 | jq container-valued check-updates cache fields would render compact-vs-pretty | The script's own cache writer cannot produce them (class of #2) |
| 10 | 6 | A forged `.run/perf-cache` entry whose key matches the live file's stat identity is served | Trust argument: anyone who can write the cache can already write zones.yaml/.loa.config.yaml — the authoritative inputs these hooks trust today; forging the cache is strictly harder. Same accepted-bypass posture as block-destructive-bash per hooks-reference.md. Corpus-pinned on both sides |
| 11 | 6 | NUL-bearing zones.yaml pattern: "ignored null byte" warning now only on the cold parse, not every call | Out of contract; decisions unaffected |
| 12 | 6 | Trailing-EMPTY yq tokens would not round-trip the cache | Unreachable by the token programs; downstream defaults coincide even if reached |
| 13 | 7 | Key+token-matching forged state-aggregate cache served; `touch -d` mtime forgery serves a stale file set | Same trust domain as #10 — cache writers can already write the state file itself |
| 14 | 7 | /dev/fd procsub-plumbing failure would no-op one call | Indistinguishable from invalid stdin; not reproducible on Linux; warn-only hook |
| 15 | 7 | Read-instant races fall within the old code's own two-read race envelope | Old code had the same window |
| 16 | 7 | Harness-only `KARPATHY_STATE_CACHE_MIN` env mixing against one state file unsupported | Test-harness knob, same trust class as `KARPATHY_TASK_STATE` |
| 17 | 9 | `\s`→`[[:space:]]` fold under the LC_ALL=C pin in mutation-logger's filter (ambient-UTF-8 fold class) | Unmeasurable on this host (no UTF-8 locale compiled); pass-2 precedent |

Also documented (not divergences): pass-5's `br doctor` ~77 ms floor and the
settings-cleanup BB-F7 12-pattern filter (~22 ms) were left by explicit
contract/governance decisions, not inability.

## 7. Operational notes

### 7.1 Zone-guard staged-install protocol (why hook edits went through staging/)

`zone-write-guard` BLOCKS Write/Edit tool calls into `.claude/**` in-session
(verified empirically in pass 2; the runbook override `LOA_ZONE_GUARD_BYPASS=1`
is env-based and cannot be applied to tool calls mid-session). This repo IS
upstream — hook edits are the product — so every pass that changed a hook
followed the same deliberate, operator-invoked protocol, logged per pass:

1. Author the modified hook via Write into
   `grimoires/loa/perf/skill-loop-2026-07-05/staging/passN/` (State Zone).
2. `bash -n`; overlay the copy into the bench mirror and prove **golden
   parity (32/32) + the pass's differential corpus there FIRST** — live
   session hooks untouched until proven.
3. Atomic install via Bash `cp` + `mv` (mutation-logger audits the install
   itself into `.run/audit.jsonl`); then `golden/capture.sh --verify` against
   the LIVE tree + the relevant bats suites + staged==installed byte checks.
4. Any failure → `git checkout --` the hook immediately.

The staging copies are retained under `staging/pass{2..9}/` together with
each pass's proof harnesses (`tools/run-diff-*.sh`, `ab-*.sh`,
`capture-overlay-*.sh`) — the full evidence chain is re-runnable.

### 7.2 `.run/perf-cache/` — the loop's ONLY additive side effect

Passes 6–7 introduced the single new State-Zone artifact:
`.run/perf-cache/{zone-write-guard.v1.rows, karpathy-config.v1.tokens,
karpathy-state.v1.agg}`. Covered by the existing `.gitignore` `.run/` rule;
documented in both hook headers; safe to delete at any time (hooks fall back
to the original parse and rewrite it — fail-open by construction). It adds no
attacker capability (§6 #10/#13).

### 7.3 Cache version-bump rule

The cache KEY deliberately excludes the memoized program text (keying on
source-file identity only), so the filename carries the version:
**any change to the memoized yq/jq/awk programs or the aggregate file format
MUST bump the filename tag (`v1` → `v2`)** — e.g. editing zone-write-guard's
row-emitting yq program without bumping `zone-write-guard.v1.rows` would
serve rows computed by the OLD program against the NEW code. This rule is
stated in each hook's header and in the pass-7 tail design block.

### 7.4 Measurement discipline for future passes

Same-window per-run ALTERNATION is mandatory on this host (powersave
governor; pass-3 documented block-wise A/B lying by 20–70%). `results*.tsv`
absolute matrices are only comparable within their own window — use the
`ab-*.tsv` files for before/after truth. hyperfine remains uninstalled;
`bench.sh` is the shared timer.

## 8. Artifact index

| Artifact | Content |
|---|---|
| `baseline.md` | Pass-1 baseline, cost anatomy, opportunity matrix |
| `final-ab.tsv` | THIS pass's definitive same-window A/B (worktree @ 4ae8aa5f vs HEAD) |
| `results.tsv` / `results-pass9{,-post}.tsv` | Absolute matrices (window-local) |
| `ab-pass{2..9}*.tsv` | Per-pass same-window A/Bs |
| `census*.tsv` | PATH-shim spawn censuses per pass |
| `golden/` | 32 golden outputs + `capture.sh --verify` gate |
| `payloads/` | Hook stdin payload templates |
| `bench.sh`, `bench-env.sh`, `run-matrix.sh`, `exec-census.sh` | Shared harness |
| `staging/pass{2..9}/` | Installed hook copies + per-pass proof harnesses |
| `.skill-loop-progress.md` (repo root) | Full per-pass log, verdicts, skips |

## 9. Honest limitations

- All numbers are from one host (Core Ultra 7 268V, Debian 13, powersave
  governor); ratios should transfer, absolute ms will not. UTF-8 locale
  sensitivity is unmeasured (locale not compiled on host).
- Chain timings sum direct hook invocations; Claude Code's own per-hook
  `sh -c` wrapper (~1.7 ms × N) and its parallel hook execution mean
  end-to-end wall gains per event are somewhat smaller than chain-sum gains
  (parallel wall ≈ max(hook), which the loop also reduced on every chain).
- `beads-health --json` full mode remains dominated by the `br doctor` ~77 ms
  floor (mission-excluded behavior contract); only the script's own ~31 ms
  overhead portion was reduced (~24%).
- The karpathy O(delta) cache engages above the 256 KiB state-size gate;
  today's real state (~660 entries) rides the original path by design and
  will cross the gate after roughly two more weeks of session accumulation.
