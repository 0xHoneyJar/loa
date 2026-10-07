# Sprint 248 — audit dissent run 1, triage (on `9fabac05`)

Two-voice run (gpt-5.5-pro via codex-headless + the claude-headless companion on claude-bedrock), all 24 chunks two-voice, `rejected_summary 0`, every sidecar empty, verdict_quality APPROVED, no `verdict_quality_error` field in any chunk envelope. Merged envelope: `adversarial-audit.json` (92 findings: 3 HIGH / 33 MEDIUM / 56 LOW).

Every finding was verified against the code by an independent Opus 5.5 verifier per chunk group (probes under `~/.cache/loa/cycle-126-dissent/probe-g1..g6/`), and the lead re-ran the decisive probes (b1 DISS-C-001's injection; the gemini-headless → AgyHeadlessAdapter registry mapping).

| Verdict | Count |
|---|---|
| REAL (fixed in round 1ap, test-first) | 11 |
| REAL-DOC (fixed in round 1ap) | 1 (+ the incidental "agy is disabled" comments and the config example's `gemini -p`) |
| REFUTED | 19 |
| REPEAT (of a prior refutation or decision in `engineer-feedback-round-1.md`) | 24 |
| DECLINE (by design, operator-controlled, or predates the sprint and is tracked) | 37 |
| **Total** | **92** |

## Fixed in round 1ap

- **b1 DISS-C-001 (command execution; sprint-introduced at round 1aa `c4b76ca2`).** A raw tab in a `diff --git` header path shifted text into lib-content.sh's manifest index, which `_lc_chunk_tok` used as an array subscript (arithmetic evaluation runs `$(…)`); reachable via `--diff-file` and gpt-review-api.sh, not `--diff-range` (git C-quotes a tab). Numeric-index guard, manifest `pri<TAB>idx<TAB>path`, include-loop `-f` guard. CMP-274.
- **e1 DISS-C-001 (HIGH raised; MEDIUM).** The stable CLI workspace refused only a denylist; it now refuses any entry. pytest `test_the_stable_workspace_refuses_any_entry_a_hop_left`; the `notes.txt` pin flipped. The live `loa-claude-ws` was empty after dozens of hops.
- **e1 DISS-001 / e2a DISS-001 (HIGH raised; pre-existing on main since a67a1a98).** The premise of the earlier refutations ("agy is disabled", efr1:1094/1112/1138) was false: `gemini-headless` is `AgyHeadlessAdapter`, the end of every stock Google CLI chain, dispatched on any host with agy installed. Dispatch unchanged (maintainer decision: an opt-in gate, raised on bd-ugmi, now P2); a once-per-process WARN names the argv / `/proc/<pid>/cmdline` exposure; the comments and `.loa.config.yaml.example` corrected.
- **a5 DISS-C-002.** `--sprint-id` shape checked in `main` (traversal via the mktemp template, run lock, move-aside, envelope dir). CMP-275.
- **a4a DISS-C-003.** The companion diagnostic is redacted before the 300-character cut and stripped of control characters. CMP-276.
- **a2 DISS-C-002.** `clean()`/`got()` strip U+061C, U+180E, variation selectors, U+FFF9–FFFB and the Tag block. NRM-66.
- **c2a DISS-C-001.** The no-digest run-tag fallback carries a POSIX cksum of the whole tag. NRM-67 (NRM-19's shape updated).
- **c2b DISS-C-003.** NRM-46's lint reads a quoted flag and strips comments only outside quotes (fixture extended).
- **c2c DISS-C-002.** `_vd_git` and `_cmp_git` isolate from a caller's GIT_TEMPLATE_DIR / GIT_EXEC_PATH / XDG git config / hooks (verdict-derive isolation test; CMP-271 leg).
- **c2d DISS-C-001.** The `_vd_shsrc` lint reads zsh/dash/ksh, `-c --`, an unquoted program and an expansion after the closing quote.
- **e2c DISS-C-001.** kf-write-lib's `san1` flattens C1 controls and U+2028/2029 (the reader's `splitlines()` would open a phantom heading). kf-write-lib.bats 34/34.
- **a3 DISS-C-001 (doc).** The lock-dir comment says what `_adv_lock_dir_ours` checks.

## Per-finding verdicts (verifier reports, verbatim)

<!-- group g1 -->
# g1 verdicts — sprint-248 audit, HEAD 9fabac05

Script = `.claude/scripts/adversarial-review.sh`; FB = `grimoires/loa/a2a/sprint-248/engineer-feedback-round-1.md`.
Probes: `/home/merlin/.cache/loa/cycle-126-dissent/probe-g1/`.

### a1-script-1 DISS-C-001 [MEDIUM] — REPEAT
`_rb` is `_adv_hop_charge` output, which is `$(( t + _adv_num_or(...) ))` (Script:2733-2737); `t` is `CONF_TIMEOUT`, already `_conf_uint`-validated at load (Script:183), so the result is always an integer. `_repair_wall_budget` comes from `_adv_repair_wall_for` (Script:3030-3039), and that function passes `LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS` through `_conf_uint` (Script:3037).
Probe: `_conf_uint K 'x[$(echo PWNED>&2)]' 600 1` prints the WARN and 600, and the substitution never runs.
This repeats FB:1167 (thirty-seventh run a3 DISS-C-003, "every input is an integer by construction").

### a1-script-1 DISS-C-002 [MEDIUM] — REFUTED
`_adv_resolve_run_tag` (Script:2372-2393) accepts a tag only when it matches `^[A-Za-z0-9_-]{1,64}$`. Any other value becomes `h<sha256-12>`, or `h<hex>` without a digest tool, or `hinvalid`. So `/`, `..` and whitespace can never reach the sidecar path.
The sidecar also lives inside the run's private `mktemp -d` workflow, and the tag issue was already fixed per FB:210.

### a1-script-1 DISS-C-003 [LOW] — REFUTED
The caller restores provenance after an accepted repair (Script:1712-1720). It deletes the model's `id_derived`/`failure_mode_derived`, re-adds only the original's markers that are `true` (never the violated field's), and copies the original's derived `id`/`failure_mode` back over the model's text.
- An injected `*_derived: true` on a field the dissenter authored is dropped.
- A model-chosen id for a derived field is discarded.
- An explicit id that was not derived can only change when it is the violated field, because `_repair_diff_ok` (Script:807-812) still compares it.

Prior fixes are at FB:178 and FB:620, with the unreachable variant at FB:943.

### a1-script-1 DISS-C-004 [LOW] — DECLINE
By design. The companion voice is the FR-2.1 default-on second chain (Script:149). A non-boolean value is said with a WARN that names the opt-out spellings (Script:196). The case-insensitive and YAML-1.1 spellings were fixed at FB:213 (eleventh run, a1 C-001) and kept on.
`budget_cents` fails closed because it is a spend cap, while `companion_voice` is a feature switch whose cost is still bounded by `budget_cents`.

### a1-script-1 DISS-C-005 [LOW] — DECLINE
`_conf_uint` (Script:137) and the companion_voice WARN (Script:196) echo a scalar from the operator's own `.loa.config.yaml` or environment, and they write only to stderr through `log`. That is not a trust boundary: the same operator writes the config and reads the terminal. The model-text surfaces are the ones that get cleaned.

### a1-script-1 DISS-C-006 [LOW] — REPEAT
The `--diff-range` gate (Script:3769-3770) requires `^[A-Za-z0-9_]` at the start of each side plus a `...` separator, and rejects `..` inside a side. Each end is then resolved to an oid by `_adv_range_oid` (Script:3664, 3781-3782) before the diff runs, so a leading `-` such as `--output=` never reaches git.
This repeats FB:1002 (twenty-sixth run a3 C-001, leading-dash half; CMP-128 pins `--output=x` and `-main...HEAD`), and the original fix is at FB:516.

### a2-script-2 DISS-C-001 [MEDIUM] — REFUTED
main validates `--type` before any dispatch: `if [[ "$type" != "review" && "$type" != "audit" ]]` at Script:3747 exits first. `_adv_record_fallback` is called only afterwards, at Script:3758, so `*`, `rejected-*` or `/` can never reach the glob or path at Script:2439/2475.

### a2-script-2 DISS-C-002 [MEDIUM] — REAL (LOW)
`clean()` (Script:1773) and `got()` (Script:395) use the class `[\u0000-\u001f\u007f-\u009f​-‏ -‮⁠-⁤⁦-⁩﻿]`. The comment at Script:1771-1772 says it strips "the bidi and zero-width format characters" so that "a row [never] render[s] unlike its bytes".
Probe (jq 1.7) on `"a؜b\U000E0041c️d​e"`: U+061C (ARABIC LETTER MARK, a bidi format character), U+E0041 (TAG) and U+FE0F all survive. Only U+200B is replaced.
- Outcome: a model-authored rejected title or description_head carries invisible tag-encoded text into `rejected_summary`, which renders unlike its bytes. That is the exact invariant the comment claims.
- Fix: add `؜᠎︀-️￹-￻\\x{E0000}-\\x{E007F}\\x{E0100}-\\x{E01EF}` to both classes. Probed: jq 1.7/Oniguruma accepts `\\x{E0000}` and the result is all spaces.
- Bats test: an NRM case feeding a rejected payload whose title holds U+061C and U+E0041, asserting that `rejected_summary[0].title` explodes to codepoints < 0xE0000 and has no 0x61C. It fails on HEAD. The same check should go through `got()` via the validator reason.

### a2-script-2 DISS-C-003 [LOW] — REFUTED
In a real run, `_rcf` is `mktemp` inside `$_ADVERSARIAL_WORKDIR` (Script:1639). main sets that variable to a private `mktemp -d` (0700, unpredictable name) at Script:3836, before any `process_findings`, and exits if it cannot be made. So `$_rcf.lockwait` is inside a directory no other account can list or write.
The `${TMPDIR:-/tmp}` fallback is reached only when a test sources the function directly. `_ADV_LOCK_EXPIRED_FILE` itself is a seam dropped outside bats (Script:2675).

### a2-script-2 DISS-C-004 [LOW] — REPEAT
A future `--since` is the same "misuse of the machine-printed run-start value" refuted as design at FB:1025 (twenty-ninth run b2 C-002). The displaced envelope's status, timestamp and counts are recorded in `metadata.displaced` (Script:2453-2458), and its file is kept as `.prev`, not deleted.
The caller is the operator's own review skill. A prompt-injected agent that can run this script can equally skip the review.

### a2-script-2 DISS-C-005 [LOW] — REPEAT
`_hb` is either the memoised or fresh `_adv_hop_charge` output, which is always an integer (see a1 DISS-C-001: `CONF_TIMEOUT` goes through `_conf_uint`, the CLI bound through `_adv_num_or`, Script:2733-2737). The catalog's `headless_timeout_seconds` goes through `_adv_pos_ceil` (awk; a whole number or return 1) and then `_adv_num_or`, so no string reaches `(( ))`. The memo is `"<hop> <int>"`, so `read -r _mh _mv` cannot truncate an integer.
This repeats FB:1167.

### a3-script-3 DISS-C-001 [MEDIUM] — REAL-DOC (LOW)
The comment at Script:2860 says "the directory is ours (0700, not a symlink)". `_adv_lock_dir_ours` (Script:2771) checks only `-d && ! -L && -O`. Mode 0700 holds only when this script created the directory (`mkdir -m 700`, Script:2775/2780).
FB:1059 (thirty-first run e3 DISS-C-004) likewise asserts "the mode and no-symlink checks apply to the lock dir", but no mode check exists.
- Not a security REAL: a pre-existing permissive directory owned by our uid can only be made by the same user, and the older lock name (`loa-headless-locks` without a uid suffix, commit 5352d21b) is a different path.
- Fix: either reword the comment to "ours and not a symlink (made 0700)", or add `[[ "$(stat -c %a -- "$1" 2>/dev/null || stat -f %Lp -- "$1")" == 700 ]]` to `_adv_lock_dir_ours`.
- Bats test for the code fix: a pre-made 0777 own-uid lock dir should make the hop run unlocked with the "not ours" line, or move to the private fallback.

### a3-script-3 DISS-C-002 [LOW] — REPEAT
`ADV_REPAIR_MAX_PER_RUN` is `readonly 5` at Script:47, so an environment value is overwritten at load. Probe: with env `ADV_REPAIR_MAX_PER_RUN='x[$(echo PWNED>&2)]'` plus `readonly ...=5`, the arithmetic gives 600 and nothing runs. The repair timeout `$2` is `CONF_TIMEOUT` (`_conf_uint`).
This repeats FB:953 (twentieth run a3 C-003, second half) and FB:1167.

### a3-script-3 DISS-C-003 [LOW] — DECLINE
By design. The shell bound mirrors cheval's own formula. cheval's `_compute_timeout` never lowers a provider `read_timeout` (`headless_cli.py:500-515`; only the headless key is clamped, at :508), and FB:271 pins that the shell does the same (NRM-18, 4000→4010).
Clamping `ct`/`rt` here would make the reaper kill a hop cheval still allows. The catalog is the operator's System-Zone file or `LOA_MODEL_CONFIG`; a branch that edits it can edit this script too.

### a3-script-3 DISS-C-004 [LOW] — DECLINE
- The input to `_adv_error_summary` is already the redacted `message_redacted` from cheval's ledger (Script:3135ff).
- The catalog branch can only capture cheval's own notes (`types.py:287-295`), whose variable part is `{raw!r}`, the operator's catalog value.
- `[A-Z][A-Z_]{4,}` admits no digits, so key and account shapes with digits never travel.
- The premise "tracked/committed envelope" is false: `grimoires/loa/a2a/*` is gitignored (`.gitignore:189`, checked with `git check-ignore`).

Narrowing the tokens to a fixed enum would drop the diagnostics FB:400/473 deliberately added.

### a3-script-3 DISS-C-005 [LOW] — DECLINE
The finding concedes this itself: environment control is operator-level. The seams are dropped at load unless a bats marker is present (Script:2675; fix at FB:390, NRM-28). Anyone who can export `BATS_VERSION=1` can equally export `PATH` or replace `flock`. This is not a boundary.

## Summary

| Verdict | Count |
|---------|-------|
| REAL | 1 |
| REAL-DOC | 1 |
| REFUTED | 4 |
| REPEAT | 5 |
| DECLINE | 5 |
| **Total** | **16** |

REAL: a2-script-2 DISS-C-002 — the clean()/got() class misses U+061C, the Tag block, the variation selectors and U+FFF9-FFFB (probed).
REAL-DOC: a3-script-3 DISS-C-001 — the "(0700, not a symlink)" comment at Script:2860 and FB:1059 claim a mode check that `_adv_lock_dir_ours` does not make.

<!-- group g2 -->
# g2 verdicts — sprint-248 audit dissent (HEAD 9fabac05)

All line numbers are `.claude/scripts/adversarial-review.sh` at HEAD unless stated. Feedback = `grimoires/loa/a2a/sprint-248/engineer-feedback-round-1.md`.

## chunk a4a

### a4a DISS-001 [MEDIUM] — REFUTED
- `metadata.rejected_sidecar` is not model-produced. Only `process_findings` sets it: it builds `$PROJECT_ROOT/grimoires/loa/a2a/${sprint_id}/adversarial-rejected-<type>[-companion][-<tag>].jsonl` (1503–1510), strips `$PROJECT_ROOT/` (1816–1819), and writes it into metadata with `--arg rejs` (1838/1844). The model's output reaches `findings` and nothing else.
- `companion.result.json` is that envelope, written by the walker (3017) into a `mktemp -d` workdir that is 0700 (3836). The fold's `rm -f` (3264) only ever sees the script's own sidecar path, and it only removes the file if it is empty.
- The tag is held to `[A-Za-z0-9_-]{1,64}` or hashed (2381–2391). The only way to push the path outside the directory is `sprint_id`, which is a5 DISS-C-002 below and is not caused by the envelope.

### a4a DISS-C-001 [MEDIUM] — REFUTED
- Same issue as a4a DISS-001, with the same evidence (1509, 1818, 1838). The path is script-authored, so there is nothing "untrusted" for `realpath` to confine.
- The TOCTOU half needs another writer in a private 0700 `mktemp -d` workdir, and the sidecar directory belongs to the same user. That is not a boundary.

### a4a DISS-C-002 [MEDIUM] — REFUTED
- The walker writes `companion.result.json` only for a hop whose status is neither `malformed_response` nor `api_failure` (3013–3018: `if [[ "$status" != "malformed_response" && "$status" != "api_failure" ]]; then … printf '%s' "$res" > companion.result.json; break`). A failed chain never writes it.
- `status` is forced to `malformed_response` when it is empty (3001). Main also removes the file unless the walker reached phase `done` (3630).
- So "file present" already means "the companion succeeded". A failed companion goes to the else branch, which writes the synthetic FAILED vq (3361–3365).

### a4a DISS-C-003 [LOW] — REAL
- Lines 3328–3329 cut the diagnostic to 300 characters (`cut -c1-300`) before the redactor (3344) and the key-shape sed (3349) run. A key that straddles column 300 is shortened below the `{12,}`/`{20,}` minimums, so its first characters survive.
- Probe (`probe-g2/companion.log`): 279 pad chars, then `AIzaFAKE…` (35 chars), run through the same cut, `log-redactor.sh` and sed. stderr shows `AIzaFAKEFAKEFAKEFAKE`, 16 secret characters unredacted. Redacting first and cutting afterwards gives `[REDACTED-KEY]`.
- The leak goes only to the operator's stderr/run log (3352). The envelope gets `_adv_error_summary`'s allowlist (2914, `grep -vE '^REDACTED'`). It still breaks the stated "the redacted raw line is operator-facing" guarantee.
- Fix: in both `_diag=` pipelines, drop `| cut -c1-300`, run the redactor and the sed, then `cut -c1-300` the result. Also strip control characters (`tr -d '\000-\010\013-\037\177'`) before `log`, because the line is provider-controlled text going to a terminal.
- Bats idea: a companion stub whose log's last line puts a fake `AIza` key (35 chars) at column 285. Assert that stderr does not contain the key's first 12 characters after `AIza`. This fails at HEAD.

### a4a DISS-C-004 [LOW] — REFUTED
- `_fold_companion` runs inside `_folded=$(_fold_companion …) || _folded=""` (4267). A jq failure anywhere in it gives `fold_failed` (4272–4275) plus a synthetic FAILED vq envelope (4285–4296). It cannot crash main or deny the review.
- `companion.rc` is the walker's own `$last_rc`, an exit status (3021), so it never has a leading zero. `cost_usd` and `findings` are shaped by `process_findings` (`--argjson cost`, the validated findings array). Neither file can be written by a model.

### a4a DISS-C-005 [LOW] — DECLINE
- `_ADV_REDACTOR_BIN` (3343) is a test seam in the operator's own environment. Whoever sets the environment already controls `PATH` (jq, git, sed, the provider CLIs) and `PROJECT_ROOT`, so constraining this one variable buys nothing.
- The script never presents the environment as a trust boundary, and CI workflows already control the whole process.

## chunk a4b

### a4b DISS-001 [MEDIUM] — REPEAT (feedback line 1002; also 584)
- Feedback 1002: "twenty-sixth run, chunk a3 C-001, leading-dash half: refuted — the `--diff-range` parser requires a word character first, before git runs; CMP-128 pins `--output=x`, `-main...HEAD`."
- At HEAD the gate is 3768–3771: `^[A-Za-z0-9_][A-Za-z0-9._/~^-]*\.\.\.[A-Za-z0-9_]…$`, with no `..` on either side. `_adv_range_diff` gets either `<oid>...<oid>` (both rev-parsed and hex-checked, 3779–3783) or that validated string.

### a4b DISS-C-001 [MEDIUM] — REPEAT (feedback line 1002)
- The leading-dash concern is the same refuted one, and it applies to `_adv_range_oid` too: the same gate runs before the value reaches `rev-parse` (3666).
- The `GIT_EXTERNAL_DIFF` half is moot. `_adv_range_diff` passes `--no-ext-diff` (3659), which disables external diff drivers, `GIT_EXTERNAL_DIFF` included, and no option can be injected after it.

### a4b DISS-C-002 [LOW] — DECLINE
- The window it describes runs from the pgrep/ps walk (3425) to the first `kill -STOP` (3433) and lasts microseconds. To exploit it, a collected descendant has to exit and its pid be recycled by an unrelated process within that window, which takes a full pid wrap (pid_max is 32768 on this host). Signalling by pid has this race in every bash process tool; pidfds are not reachable from bash.
- The KILL leg is identity-gated (`_adv_kill_same` / `_adv_is_same`, 3470–3483). `_adv_reap_primary` checks the root's start token before it does anything (`_ADV_PRIMARY_START`).
- "An empty token means the pid alone decides" is documented design (`_adv_pid_tokens`, 3467). `_adv_proc_start` reads `/proc` first, so `ps` is not required.

### a4b DISS-C-003 [LOW] — DECLINE
- The cancel (3443) follows directly after the CONT pass. Two things must both happen for the group KILL to land on a recycled pgid: the freeze passes take longer than the 10 s watchdog delay, and the watchdog's pid is reused as a new session leader. That is the same pid-wrap class as C-002.
- The non-setsid fallback (3456–3458, macOS) puts the watchdog in the reviewer's group. That is the residual the 33rd-run fix knowingly accepted (feedback 801: "its own session under setsid"). Only an operator's group-wide SIGKILL of the reviewer reaches it, and the watchdog ignores HUP.

## chunk a5

### a5 DISS-C-001 [MEDIUM] — REFUTED
- `_adv_record_fallback` checks every precondition the finding says is missing:
  - status whitelist: `failed|workdir_unavailable|nothing_to_review|budget_exceeded|diff_range_failed` (2429–2433)
  - strict ISO-8601 UTC `--since` (2435–2437)
  - sprint-id shape (2438)
  - the run lock is taken, and a live holder is refused (2441–2445)
  - a non-regular node is refused (2448–2451)
- `failed` without `--since` never records over a standing envelope (2475–2478). An envelope newer than `--since` is refused for every status (2471–2473, 2486–2490). An empty `--since` is a usage error (3757).
- The record is written as `findings: []` with a failure status and the displaced envelope's summary (2505–2508). Nothing is bypassed.

### a5 DISS-C-002 [MEDIUM] — REAL (LOW)
- `main` checks only that `sprint_id` is non-empty (3750). The shape check `^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ && != *..*` exists only inside `_adv_record_fallback` (2438). On the review path the raw value reaches:
  - `mktemp -d "${TMPDIR:-/tmp}/adversarial-${sprint_id}-XXXXXX"` (3836)
  - `_adv_take_run_lock "$PROJECT_ROOT/grimoires/loa/a2a/${sprint_id}"` (3994)
  - `_adv_move_aside` of `grimoires/loa/a2a/${sprint_id}/adversarial-<type>.json` (4011)
  - `process_findings`' `mkdir -p` of the sidecar directory (1504)
  - `write_output`'s `mkdir -p` and `mv` (`write_output`, `output_dir=…/a2a/${sprint_id}`)
- Probe: `mktemp -d "$T/adversarial-x/../../esc-XXXXXX"` fails while `$T/adversarial-x` is missing. Once that directory exists (on a shared `/tmp` any user can create it), the same call creates `…/probe-g2/esc-HrUZKd` outside `$T`. With `--sprint-id 'x/../../../../elsewhere'`, the lock, the `.prev` rename and the envelope then land outside `grimoires/loa/a2a/`.
- The value comes from the skill (LLM-composed, `<sprint_id>` placeholder), so it does cross a boundary. Exploiting it needs a pre-created `adversarial-<prefix>` directory, hence LOW.
- Fix: move the 2438 regex into `main` right after the emptiness check at 3750, before the `--record-fallback` branch and before any sink.
- Bats idea: `mkdir "$TMPDIR/adversarial-x"`, run main with `--sprint-id 'x/../../../esc' --diff-file <f>`, and assert exit 2, "invalid --sprint-id", and no `$PROJECT_ROOT/grimoires/esc` or `$PROJECT_ROOT/esc` created. This fails at HEAD.

### a5 DISS-C-003 [LOW] — REFUTED
- `_adv_cleanup_on_exit` (3696) removes the range diff itself: `[[ -n "${_ADV_RANGE_DIFF:-}" ]] && { command rm -f -- "$_ADV_RANGE_DIFF" … }` (3706). Replacing the first trap leaves no file behind.

### a5 DISS-C-004 [LOW] — REFUTED
- The fallback to `_rr="$diff_range"` (3778–3783) does not happen in practice. A rev that fails `rev-parse --verify "X^{commit}"` also fails the three-dot diff, which needs a merge base of two commits, and that becomes the `diff_range_failed` refusal (3784–3787).
- Probe (`probe-g2/r2`): a ref to a tree gives `oid rc=1` and `git diff HEAD...tt` gives rc=128. A missing ref gives rc=128.
- Adoption also requires a matching `diff_oids`, not ref names alone (reviewing-code `resources/ADVERSARIAL-REVIEW.md:30`).

### a5 DISS-C-005 [LOW] — DECLINE
- Deliberate design: the eighth-run fix put the aggregator's reason on the envelope instead of discarding it (feedback 164).
- `grimoires/loa/a2a/*` is gitignored (`.gitignore:189`, confirmed with `git check-ignore`), so nothing lands in a committed artefact.
- The aggregator's stderr is about sidecar structure, e.g. "INV-4: voices_succeeded_ids contains duplicates" (feedback 913), and is capped at 240 characters.

## Counts

| Verdict | Count | Findings |
|---|---|---|
| REAL | 2 | a4a DISS-C-003 (truncate-before-redact), a5 DISS-C-002 (sprint_id unvalidated on the review path) |
| REAL-DOC | 0 | — |
| REFUTED | 7 | a4a DISS-001, a4a DISS-C-001, a4a DISS-C-002, a4a DISS-C-004, a5 DISS-C-001, a5 DISS-C-003, a5 DISS-C-004 |
| REPEAT | 2 | a4b DISS-001, a4b DISS-C-001 (feedback 1002) |
| DECLINE | 4 | a4a DISS-C-005, a4b DISS-C-002, a4b DISS-C-003, a5 DISS-C-005 |
| Total | 15 | |

<!-- group g3 -->
# g3 verdicts (chunks b1, b2, c1a, c1b, c1c) — HEAD 9fabac05

Feedback file cited as `efr1:<line>` = grimoires/loa/a2a/sprint-248/engineer-feedback-round-1.md.

## chunk b1

### b1 DISS-001 [MEDIUM] — REPEAT
- verdict-derive.sh:128 records an empty `--envelope` in `_EMPTY_FLAGS`. verdict-derive.sh:402-406 then warns "--envelope given empty — the sibling … beside --file is read instead" in both plain and `--json` modes, so the fallback is never silent.
- This was decided twice already: efr1:214 (eleventh run, b DISS-C-002, "an empty value reads as not given") and efr1:339 (sixteenth run, c2d C-002, warning added).
- The help's "a missing explicit path is a usage error" (line 69) means a path that is not found. Lines 154-156 enforce that.
- Nit: the help does not say what an empty value does. Adding one clause would close the gap. That is not a new defect.

### b1 DISS-C-001 [MEDIUM] — REAL (command execution through an array subscript; `--diff-file` input only)
- lib-content.sh:199/215 writes the manifest as `pri<TAB>path<TAB>idx`. The path is `BASH_REMATCH[1]` of `^diff --git a/(.+) b/` taken over the raw diff. Every loop reads it back with `IFS=$'\t' read -r priority filepath chunk_idx`, so a raw tab in the header path moves the attacker's text into `chunk_idx`.
- The candidate and reservation pre-scans (lines 284, 296) check `-f chunk_$idx` first. The include loop (lines 352-360) only checks `-n`. Its `cat` fails without stopping the run: errexit is off inside `$(…)` and no `inherit_errexit` is set. It then calls `_lc_chunk_tok`, and line 164's `${_lc_tok[$2]:-}` / `_lc_tok[$2]=` evaluates `$2` as an arithmetic subscript.
- Probe (`probe-g3/probe1.sh`, `probe2.sh`, bash 5.2.37, with adversarial-review.sh's own `set -euo pipefail`): a 3-file diff over the 500-token budget whose middle header is `diff --git a/x<TAB>PATH[$(touch PWNED1)] b/x` creates `PWNED1`. A name that is not set (`q[...]`) creates `PWNED2` once `-u` is dropped. Under `-u`, any set variable (PATH, HOME) works.
- Reach: this went in at round 1aa (`c4b76ca2`, the memo). The old code never used the index as a subscript. `--diff-range` cannot reach it, because git always C-quotes a tab (`"a/x\tq"`), so the regex does not match. `adversarial-review.sh --diff-file <hand-built or received .patch>` and gpt-review-api.sh:286 (`prepare_content` over its content file) both pass raw bytes through, and the payload runs in the reviewer's shell with its credentials.
- Fix: in `_lc_chunk_tok`, refuse any index that is not a number with `[[ "$2" =~ ^[0-9]+$ ]] || return 1`. Give the include loop the same `-f "$temp_dir/chunk_${chunk_idx}"` guard the pre-scans have. Better still, write the manifest as `pri<TAB>idx<TAB>path` and read it as `read -r priority chunk_idx filepath`, so the path takes the rest of the line.
- Test (fails first): a CMP case that sources lib-content.sh under `set -euo pipefail`, feeds prepare_content an over-budget diff with the header ``diff --git a/x$'\t'PATH[$(touch "$T/pwned")] b/x``, and asserts `[ ! -e "$T/pwned" ]` and that the other two files are still ranked and included.

### b1 DISS-C-002 [LOW] — DECLINE (partial REPEAT)
- verdict-derive.sh:194-206 unsets `GIT_CEILING_DIRECTORIES`, `GIT_DISCOVERY_ACROSS_FILESYSTEM` and `$(git rev-parse --local-env-vars)`. That includes `GIT_CONFIG_PARAMETERS`/`GIT_CONFIG_COUNT`, as the probe on git 2.47.3 shows. This was a deliberate thirty-eighth-run choice (efr1:892, c2d DISS-C-004): a caller's environment never picks the repository.
- The values that are dropped belong to the caller's environment. The operator's environment is not a trust boundary, and a PR cannot set it. The directory searched is the envelope's own (the sprint's a2a directory, or the caller's own `--envelope`), and walking up from there reaches the checkout's own `.git/config`, which is local and never committed.
- Git's ownership check (`safe.directory`) is unaffected by the unset. Removing `-c` config can only take away a `safe.directory` allowance, never add one, so a repository owned by another user is still refused.
- The diff.external half was refuted by probe in the thirty-ninth run (efr1:907).

## chunk b2

### b2 DISS-C-001 [MEDIUM] — DECLINE (by design; premise partly false)
- The companion voice defaulting on is maintainer-approved FR-2.1 (prd.md, sdd.md). The whole block ships `enabled: false` (`.loa.config.yaml.example:1391`/`1451`), so nothing leaves the host until the operator opts in.
- The claim that adding an API key changes which vendors get the diff is false. The companion family is always the other family of the primary (`_companion_chain`, adversarial-review.sh:2345). A key only decides whether that same vendor is reached over HTTP or through its CLI hop (`gpt-5.5` versus `codex-headless`, both OpenAI). The config comment says exactly that: "Credential presence only decides where the companion chain starts".
- "an absent key is true" refers to the `companion_voice` config key, not an API key.
- The resolved chain and family are already recorded in the envelope (`metadata.companion_voice.chain`/`family`, and the "Companion voice (<family> family): <chain>" log line at line 4069). `secret_scanning.enabled: true` redacts before sending.

### b2 DISS-C-002 [MEDIUM] — REPEAT
- The doc already says `budget_cents` is "not a spend ceiling", lists the calls it does not count, and gives the count and wall-clock bounds (`.loa.config.yaml.example:1393-1402`). Repairs are bounded per voice at 5 findings × at most 3 hops (`ADV_REPAIR_MAX_PER_RUN` is readonly 5, efr1:953).
- Earlier verdicts of design: efr1:1071 (thirty-second run, e2a DISS-C-002), efr1:1118 (thirty-fourth run). The per-voice budget is PRD FR-1.9 ("each voice ≤ budget").
- An aggregate spend cap is the operator's spend decision (bead bd-xqjw).

### b2 DISS-C-003 [MEDIUM] — REFUTED
- claude-headless runs with `--tools ""` and `--permission-mode plan` (claude_headless_adapter.py:20-25, 255-273).
- codex-headless runs with `--sandbox read-only`, `--ephemeral`, `--ignore-user-config`, and an empty `-C` cwd (codex_headless_adapter.py:27, 83-115, 240-259).
- Prompt injection in the diff therefore reaches a model with no tools and no write path.
- PATH resolution uses the operator's own PATH, which a PR cannot set. That is not a trust boundary the code claims to defend.

### b2 DISS-C-004 [LOW] — DECLINE
- Hop names are never put into a command. `_adv_companion_chain_conf` (adversarial-review.sh:739-752) keeps only `!!str` scalars matching `\A[A-Za-z0-9._/:-]{1,128}\z` and drops anything else with a WARN. The kept names are passed to cheval as a model id, which resolves them through the catalog. An unknown name fails as that hop and is recorded.
- Independence is judged from the voices that actually answered (`companion_voice.independent`, `counted_as duplicate_voice`). The comment documents this and `shared_hops` lists the overlap.
- "Used as given" is the documented operator-override contract.

### b2 DISS-C-005 [LOW] — REPEAT
- efr1:1086 (thirty-third run, b2 DISS-C-001): "`companion_voice: false` avoids the degraded marker" was refuted as design. The opt-out is visible as `planned: false` and `voices_planned 1`, and the marker is for an unplanned loss.
- Also efr1:1103 (thirty-fourth run).

### b2 DISS-C-006 [LOW] — DECLINE (predates the sprint, out of scope)
- The fail-open row is on main unchanged in meaning. `git show main:.claude/skills/auditing-security/SKILL.md` line 61 reads "Continue — fail-open, preserving the prior semantics". This sprint only regenerated the include text (hash 46df906b → 11663b90).
- The guardrail screens the operator's invocation prompt and arguments, not the diff sent to the dissenters. Pre-send redaction is `secret_scanning`.
- Deleting or breaking a System Zone script already takes System Zone write access.

## chunk c1a

### c1a DISS-C-001 [LOW] — DECLINE
- `_cmp_git` (adversarial-review-companion.bats:389) is a test-only wrapper. It also isolates HOME, XDG_CONFIG_HOME, global config and system config.
- `protocol.file.allow=always` is needed by CMP-142 (line 3391) and CMP-180 (line 4077). Each runs `submodule add` from a local repository it created under `$T`.
- No fixture clones a repository it did not create, so nothing reaches the CVE-2022-39253 shape. Moving the flag onto those two calls would be a style choice, not a fix.

### c1a DISS-C-002 [LOW] — DECLINE (REPEAT in substance)
- `_sweep_stale_suite_dirs` (companion bats:293) deletes only `<a2a>/<prefix>-<pid>` and that directory's own `.reap-*` siblings for a marker whose pid is dead. It never follows a link, and it re-checks the marker's inode before removing it.
- To plant a marker, an attacker needs write access to the gitignored a2a directory, and with that access they can delete the directory directly. Nothing is gained.
- The marker design is efr1:560. The foreign-marker angle was declined at efr1:1181 (thirty-eighth run, c1a DISS-C-002).

### c1a DISS-C-003 [LOW] — DECLINE
- `sk-ant-api03-SECRETSECRETSECRETSECRET1234` (companion bats:205) has 28 characters after the prefix. Gitleaks' Anthropic rule needs `sk-ant-api03-` followed by 93 characters and then `AA`, so it does not match. It is a fake value used to exercise the redaction mask.
- CMP-13 (line 624) tests which companion chain is chosen. CMP-4 and CMP-6 already check that the key value never leaks, on the same keyed path.
- Adding the same leak check to CMP-13 would be cheap, but it is a test nicety, not a defect.

## chunk c1b

### c1b DISS-C-001 [LOW] — REPEAT
- An unusable run-lock directory leading to an unguarded run with a log line is the CMP-93 design. The same report was refuted as design at efr1:1117 (thirty-fourth run, e2a DISS-C-002).
- A missing lock makes the single-writer output nondeterministic, not unsafe. verdict-derive's sidecar and envelope checks still fail closed on a torn or mismatched envelope.

### c1b DISS-C-002 [LOW] — REFUTED
- `_adv_pid_tokens` (adversarial-review.sh, just before `_adv_kill_same`) records `-` for a pid that is already gone, and `_adv_is_same` never signals `-`. An empty token occurs only when the pid passed `_adv_pid_alive` and then disappeared within the next microseconds, before its `/proc/<pid>/stat` read.
- After that, the bare pid is signalled only if it is reused within the reap grace (`LOA_ADVERSARIAL_REAP_GRACE_SECONDS`, default 5), by the same user. That needs a full wraparound of the pid space (32768 pids here) within 5 s.
- The reported "~1000 s" window is wrong. Collection and the KILL happen at reap time, and only the grace separates them.
- The suggested ps-lstart retry would bring back the mixed-form comparison the twenty-eighth regression removed (CMP-172: on a /proc host the token's form is fixed).
- The empty-token yield on the pre-freeze read was already handled at efr1 (thirty-eighth run, a4 DISS-C-002, in `_adv_reap_companion`).

### c1b DISS-C-003 [LOW] — REFUTED (REPEAT)
- adversarial-review.sh:2675 unsets `_ADV_FLOCK_BIN`, `_ADV_PGREP_BIN`, `_ADV_REDACTOR_BIN` and the other seams at load unless a bats marker (`BATS_TEST_FILENAME`/`BATS_VERSION`) is present. That is the opt-in test-mode gate the finding asks for, and its own conditional says the finding then does not apply.
- Acted on at efr1:390 (chunk a2 C-005).

## chunk c1c

### c1c DISS-C-001 [MEDIUM] — REPEAT
- `.git/info/attributes` applying to `--diff-range` was decided as the operator's local policy. CMP-186 (companion bats:4185, thirtieth run, a3 DISS-C-002) and CMP-231 (line 4964) pin it, and efr1:848 says so explicitly (".git/info/attributes still applies (CMP-231)").
- The committed `.gitattributes` half was fixed (empty-tree `GIT_ATTR_SOURCE`). Efr1:1068 refuted the repeat.
- Under this threat model, an actor that can write `.git/` can also rewrite hooks or the index. Writing to `.git/` was never in scope as a PR-controlled value.

### c1c DISS-C-002 [MEDIUM] — DECLINE (predates the sprint; operator-only)
- The override is on main in both SKILL.md files: auditing-security line 166 and reviewing-code line 211 ("Emergency override only via `LOA_ADVERSARIAL_REVIEW_ENFORCE=false`"). The hook prints it in its own block message (adversarial-review-gate.sh:172, 234).
- The new resource text names the operator as the actor ("or the operator sets …, noted in sprint notes").
- The hook reads the variable from the harness process environment (gate.sh:84). An agent's Bash `export` does not reach a PreToolUse hook, so the agent cannot open the gate this way.

### c1c DISS-C-003 [LOW] — DECLINE
- CMP-171 (companion bats:3914) has to use `${TMPDIR:-/tmp}/adversarial-<sprint>-*` because that is the path the production teardown sweeps: the script's workdir is a literal `/tmp/adversarial-<sprint>-<pid>` (efr1:924).
- The link it plants points into `$T`. If another local user pre-creates that path as a directory, the result is a spurious test failure, not damage. The shared multi-user /tmp is not the suite's threat model.
- An optional hardening is to assert `[[ -L "$lnk" ]]` after `ln -s`.

## Counts

| Verdict | Count | Findings |
|---|---|---|
| REAL | 1 | b1 DISS-C-001 |
| REAL-DOC | 0 | — |
| REFUTED | 3 | b2 DISS-C-003, c1b DISS-C-002, c1b DISS-C-003 |
| REPEAT | 5 | b1 DISS-001, b2 DISS-C-002, b2 DISS-C-005, c1b DISS-C-001, c1c DISS-C-001 |
| DECLINE | 9 | b1 DISS-C-002, b2 DISS-C-001, b2 DISS-C-004, b2 DISS-C-006, c1a DISS-C-001, c1a DISS-C-002, c1a DISS-C-003, c1c DISS-C-002, c1c DISS-C-003 |
| Total | 18 | |

<!-- group g4 -->
# g4 verdicts — sprint-248 audit dissent, chunks c2a–c2e (HEAD 9fabac05)

Feedback refs are line numbers in `grimoires/loa/a2a/sprint-248/engineer-feedback-round-1.md`. The probes are in `~/.cache/loa/cycle-126-dissent/probe-g4/`.

### c2a DISS-C-001 [LOW] — REAL
- `.claude/scripts/adversarial-review.sh:2385-2388` (`_adv_resolve_run_tag`, no-digest branch): `_h="${_h:0:200}-$(( ${#_h} / 2 ))"` keeps the first 100 bytes plus the length. The next line's WARN says "distinct raw tags never share a file". That is false beyond 100 bytes.
- Probe (fn.sh, PATH without sha256sum/shasum): `x×149 + "."` and `x×149 + ","` both resolve to `h7878…78-150`, so the two tags share one sidecar name.
- NRM-19 (`tests/unit/adversarial-review-normalise.bats:545`) only asserts the `^h[0-9a-f]{200}-152$` shape. It never compares two long tags that share a prefix.
- Minimal fix: past 100 bytes, append a POSIX `cksum` of the whole raw tag (`…-<len>-<crc>`), or else soften the WARN. Proof: NRM-19 gets two 150-byte tags that differ only in the last byte and asserts their names differ. That assertion is red on HEAD.
- Reach: this needs a host with neither sha256sum nor shasum and two invalid tags over 100 bytes. The round-1u fix (line 364) chose the cut deliberately but did not cover this collision.

### c2a DISS-C-002 [LOW] — REPEAT
- Lines 1170 (37th run c2a DISS-C-001: "`read -ra` loses a second alias line", refuted because `_adv_cred_aliases` is one line by contract) and 1129 (35th run). There is no new angle.
- `_adv_cred_aliases` (`adversarial-review.sh:572-579`) is a closed `case` of literal identifiers, so no name can start with `-`. The production probe `_adv_cred_present` (:583) reads it with the same `read -r -a`.

### c2b DISS-C-001 [MEDIUM] — REPEAT
- Line 799 (33rd run a2 DISS-C-003) already fixed this: `clean()` (:1773) and `got()` (:395) strip `[\u0000-\u001f\u007f-\u009f​-‏ -‮⁠-⁤⁦-⁩﻿]`, which covers C1, U+2028/9, the bidi overrides and isolates, the zero-width characters and the BOM.
- NRM-52 (`adversarial-review-normalise.bats:1663`) pins it with U+202E, U+2066/2069, U+2028/2029, U+0085, U+200B, U+200F and U+FEFF in the title, anchor, description, category and severity. It asserts that no such code point survives anywhere in `rejected_summary`.

### c2b DISS-C-002 [LOW] — DECLINE
- The behaviour is by design. Line 390 made the seams bats-gated: `adversarial-review.sh:2675` unsets `_ADV_FLOCK_BIN`, `_ADV_PGREP_BIN`, `_ADV_REDACTOR_BIN` and the other seams unless a bats marker is set. Line 347 pins the same convention for `LOA_ADVERSARIAL_NO_FM_DERIVATION` (NRM-25). This is the framework's test-mode rule. Only L7 primitives need a second `*_TEST_MODE` opt-in.
- The failure mode needs an attacker who already controls the environment. That attacker already controls PATH, so they choose which `flock` and `jq` run anyway. A second opt-in variable lives in the same environment and adds no boundary.

### c2b DISS-C-003 [LOW] — REAL (latent lint gap; parts (a) and (c) only)
- I extracted NRM-46's lint (`adversarial-review-normalise.bats` heredoc after line ~1340) to `probe-g4/lint.py` and ran it on a 3-line fixture:
  - (a) `jq -n "--arg" x "$payload" .` passed the lint.
  - (c) `jq -n --arg a "b  # c" --arg y "$payload" .` passed the lint, because the `\s{2,}# ` comment strip cuts inside the quoted operand.
  - The control `jq -n --arg y "$payload" .` was flagged (rc 3).
- No line in the script uses form (a) or (c) today (grep for a quoted `--arg` flag finds nothing), so this is latent, the same class as line 741's fixed lookahead gap.
- (b) A flag held in a variable cannot be linted by any line regex; DECLINE that part. (d) Refuted: `last_error`/`_diag` are capped at `cut -c1-300` (:3321-3322, `_companion_ledger_message` …`| cut -c1-300`); `reject_reason` uses `got()`, which is sliced to 32 characters (:395); `_vq_err` is capped at `cut -c1-240` (:4396); `_enforced_err` and `_ff_why` are literals; `stop_reason` is cheval's normalised enum field.
- Minimal fix: widen the flag match to `["']?--(?:argjson|arg)["']?\s+`, apply the trailing-comment strip only outside quoted spans, and add both bypass lines to the must-fail fixture. Proof: the two new fixture lines are red on HEAD's lint.

### c2c DISS-C-001 [MEDIUM] — REFUTED
- "No caller is visible" is false. There are three callers: `tests/unit/verdict-derive.bats:1129` passes `$reader`, set by `… & local reader=$!` (:1117), and :1652 and :1658 pass `$r`, set by `sleep 300 3>&- & r=$!` on the line before. Each gets a `$!` captured right after `&`, so the pid is never empty, 0 or negative. `kill -KILL 0` and `kill -KILL -1` are unreachable.
- The stale-`$t` recycle window is one second and covers only pids that were the reader's own descendants. The re-snapshot is the 33rd-run design (TERM-ignoring readers, reparented children). A recycled pid in that window would be test-hygiene noise, not a trust boundary. A `[[ $reader =~ ^[1-9][0-9]*$ ]]` guard would be harmless but is optional.

### c2c DISS-C-002 [LOW] — REAL
- `_vd_git` (`tests/unit/verdict-derive.bats:22-27`) has the comment "no caller config, and none of a caller's repository environment". Two of the variables this finding names are not scrubbed.
- Probe (`probe-g4/vdgit.sh`, HEAD's helper verbatim) with `GIT_TEMPLATE_DIR=<dir with a failing hooks/pre-commit>` and `XDG_CONFIG_HOME=<dir with git/ignore '*.md'>`:
  - The output was `HOOK-RAN` and `commit_rc=1`, so the caller's template hook ran inside the fixture repo.
  - `ls-files` listed only `b.txt`. The fixture's `a.md` was silently dropped by the caller's XDG ignore. `GIT_CONFIG_GLOBAL=/dev/null` does not stop git reading the default `core.excludesFile` and attributes paths under `$XDG_CONFIG_HOME`.
- The `GIT_CONFIG_PARAMETERS` and `GIT_CONFIG_COUNT` half is refuted: `git rev-parse --local-env-vars` lists both, and the fallback only matters when that git call fails.
- Minimal fix: inside the subshell, also `unset GIT_TEMPLATE_DIR GIT_EXEC_PATH` and set `XDG_CONFIG_HOME=/nonexistent` (or pass `-c core.hooksPath=/dev/null -c core.excludesFile=/dev/null -c core.attributesFile=/dev/null`). Proof: add `GIT_TEMPLATE_DIR=…` and `XDG_CONFIG_HOME=…` legs to the "fixture repository's git never acts on a caller's" test (:1628). They are red on HEAD, as the probe shows.

### c2d DISS-C-001 [LOW] — REAL (latent lint gap)
- `_vd_shsrc` (`verdict-derive.bats:1568-1575`): `sre` requires the word `(ba)?sh` at a word start and an option run of `-[A-Za-z]+` only.
- Probe with HEAD's three grep patterns: `zsh -c "x $d"`, `bash -c -- "x $d"`, `bash -c x$d` and `bash -c "x"$d` all produced no hit.
- Neither suite contains any of these forms today; a grep across verdict-derive.bats and verdict-observations-section.bats finds only the lint's own test title and fixture. So the gap is latent, the same class the 38th run widened (sh, flag groups).
- Minimal fix: use a shell matcher of `(ba|da|z|k)?sh|\$\{?SHELL\}?`, allow `--` in the flag run, and add patterns for an unquoted program and a post-quote expansion (`-c[[:space:]]+[^'"[:space:]]*\$`, `-c[[:space:]]+"[^"]*"\$`). Add each of the four lines to `shfx`. Proof: the new `shfx` entries are red on HEAD.
- The `bash -s`/`<<<`/`source` part is DECLINEd: those forms read no program from argv, so they are outside this lint's stated class (a `-c` program).

### c2d DISS-C-002 [LOW] — DECLINE
- The legacy branch is by design. Lines 303, 393 and 851 adjudicated it: a pre-FR-2 envelope must stay a pass, otherwise committed historical sprints read INCONSISTENT on a fresh checkout (line 851).
- A sidecar newer than the envelope still counts (line 303). A sidecar that git tracks is judged by HEAD content, not by mtime (line 851).
- The writer that would forge the downgrade is the reviewed agent itself. It could equally delete the sidecar, which no producer-file gate can stop; the finding concedes as much. A writer-version gate would be a new contract, not a defect in this sprint.

### c2d DISS-C-003 [LOW] — REFUTED
- The premise "if `_vd_git` scrubs only the three tested variables" is false. `verdict-derive.bats:25` unsets `GIT_COMMON_DIR`, `GIT_OBJECT_DIRECTORY`, `GIT_ALTERNATE_OBJECT_DIRECTORIES`, `GIT_CEILING_DIRECTORIES`, `GIT_DISCOVERY_ACROSS_FILESYSTEM`, `GIT_NAMESPACE`, `GIT_PREFIX`, `GIT_IMPLICIT_WORK_TREE` and everything in `git rev-parse --local-env-vars`. The probe printed that list, which includes `GIT_COMMON_DIR` and `GIT_OBJECT_DIRECTORY` again. So the claimed failure (fixture objects or refs landing in the caller's store) cannot happen.
- `GIT_CONFIG_GLOBAL=/dev/null` and `GIT_CONFIG_NOSYSTEM=1` are set, so a caller's `core.hooksPath` or `init.templateDir` config is never read. The real residue (`GIT_TEMPLATE_DIR`, the XDG ignore file) is c2c DISS-C-002 above. Extending the `gv` loop there covers both findings.

### c2e DISS-C-001 [MEDIUM] — DECLINE (pre-existing, tracked)
- This is bead `bd-rk9o` (P2, OPEN, labels security/guardrails), titled "every run-mode input-guardrail check errors and falls open". The bead already states the deterministic reading this finding asks for, and the fixture README's table names it.
- The sprint touched only `autonomous-agent/SKILL.md`'s generated include wording (`git diff 2079e719...HEAD`: 4 lines of prose). Neither `guardrails-orchestrator.sh` nor the enforcer changed. Re-prioritising the bead is the maintainer's call.

### c2e DISS-C-002 [MEDIUM] — DECLINE (pre-existing, out of scope)
- The sprint's only change to `.claude/adapters/tests/test_epistemic_scopes.py` is a `sys.path.insert` line (36th run c2e DISS-C-004). `context_filter.py` and `model-permissions.yaml` are unchanged in `2079e719...HEAD`.
- `filter_context` and `audit_filter_context` are only exported (`loa_cheval/routing/__init__.py:30,86`). No dispatch path calls them, so no epistemic boundary is enforced in production. The all-full default is the documented pre-v7 backward compatibility.
- A fail-closed unknown-model profile would be a new feature for a filter that is not wired in, so it belongs in a follow-up bead if wanted.

### c2e DISS-C-003 [LOW] — DECLINE (pre-existing, tracked)
- This is bead `bd-mfqp` (P3, open), named in the fixture README table row 02 and at line 456 ("pre-existing"). The sprint did not change `workspace-cleanup.sh` or Phase 0.0.

### c2e DISS-C-004 [LOW] — DECLINE
- This is the same filter as c2e DISS-C-002: it is not wired into any dispatch, and neither it nor the yaml changed in this sprint. A test pinning `context_access` on real entries would guard a boundary that production never applies. It would be a reasonable follow-up only together with wiring the filter in.

### c2e DISS-C-005 [LOW] — DECLINE (by design / enhancement)
- `failure_mode_derived: null` on a repaired violated field is deliberate (line 828 and the comment at `adversarial-review.sh:1715`): the repaired text is the model's, not the script's derivation, so it must not be labelled derived.
- `_repair_diff_ok` (:1712) and the byte-diff guard (Constraint 4) only let the repair rewrite the violated field. That field was missing or empty in the dissenter's payload, so no dissenter assertion is overwritten.
- The envelope's `repaired_count` records the repair. A per-finding `repaired_fields` marker is a new provenance feature, not a defect.

### c2e DISS-C-006 [LOW] — REPEAT
- Lines 139 and 891 (38th run c1b DISS-C-001). `_adv_lock_dir` (`adversarial-review.sh`, after `_adv_cli_lock_dir`) creates the directory with `mkdir -m 700` and requires `-d && ! -L && -O` (`_adv_lock_dir_ours`). Otherwise it falls back to a private `${XDG_CACHE_HOME:-$HOME/.cache}/loa/headless-locks-<uid>` under the same check. CMP-255 pins this. A planted directory or symlink in `/tmp` therefore never captures or denies the lock.

## Counts

| Verdict | Count | Findings |
|---------|-------|----------|
| REAL | 4 | c2a DISS-C-001, c2b DISS-C-003 (a/c), c2c DISS-C-002, c2d DISS-C-001 |
| REAL-DOC | 0 | (c2a-001's WARN text and c2c-002's helper comment are false, but both are folded into their REAL entries) |
| REFUTED | 2 | c2c DISS-C-001, c2d DISS-C-003 |
| REPEAT | 3 | c2a DISS-C-002, c2b DISS-C-001, c2e DISS-C-006 |
| DECLINE | 7 | c2b DISS-C-002, c2d DISS-C-002, c2e DISS-C-001..005 |
| Total | 16 | |

<!-- group g5 -->
# g5 verdicts — chunks d-cheval, e1-adapters, e1b (sprint-248 audit, HEAD 9fabac05)

Probes: /home/merlin/.cache/loa/cycle-126-dissent/probe-g5/ (route.py, ws.py, base.py, test_g5_stable_ws.py). No repo writes. No real CLI was run.

## A premise to correct first: agy is NOT disabled

The round-1 refutations (engineer-feedback-round-1.md:1094, 1112, 1138) and the adapter's own comments (agy_headless_adapter.py:36, "before re-enabling agy"; :133, "before agy is re-enabled") call agy "disabled". Nothing in the code disables it:
- `providers/__init__.py:55` registers `"gemini-headless": AgyHeadlessAdapter`. `cheval.py:353` maps provider `google`'s kind:cli entries to `gemini-headless`. So `google:gemini-headless` always dispatches **agy**. `GeminiHeadlessAdapter` is not in the registry, so cheval cannot dispatch it at all.
- route.py probe against stock `.claude/defaults/model-config.yaml`: `gemini-3.1-pro` resolves to `[google:gemini-3.1-pro-preview http, google:gemini-2.5-pro http, google:gemini-headless cli]`. `gemini-2.5-pro`, `google:gemini-2.5-flash` and the `gemini-headless` alias also end in agy. Every Google chain in the defaults (model-config.yaml:216-309) ends in agy, `deep-thinker` points at a Google model, and flatline-readiness.sh:145 defaults the tertiary to `gemini-2.5-pro`. Under `hounfour.headless.mode: cli-only` (the documented zero-key path, and this repo's own .loa.config.yaml:109), agy is the only Google rung left.
- "Disabled" is really two facts about this host. The tertiary line in this repo's .loa.config.yaml:341-345 is commented out, and `agy` is not on PATH (`which agy`: not found). On any host where an operator installs agy, as the adapter's ConfigError tells them to, stock config dispatches it.
- There is also a stale doc. `.loa.config.yaml.example:829` says "gemini-headless: routes through `gemini -p`", but it routes through `agy -p`.

---

### d-cheval DISS-C-001 [MEDIUM] — DECLINE
- The mechanism is accurate. `_dir_trustworthy` (headless_cli.py:84-94) only calls `_acl_extended` when S_IWGRP is set. On NFSv4, a write grant to a named user does not show in the mode bits.
- It is outside the threat model. An account holding write on any ancestor of $HOME (or on $HOME) already owns this account: it can rename-swap the home directory or replace its dotfiles. Planting CLAUDE.md adds nothing to that.
- The fix would break NFS hosts. An NFSv4 client lists `system.nfs4_acl` on essentially every inode. Calling `_acl_extended` on every ancestor would refuse every NFS-backed $HOME and $TMPDIR, so those hosts would get no headless voice at all.
- The previous round already did the useful part: any `system.*acl*` name now counts on the group-writable branch (round 1an, feedback:908).

### d-cheval DISS-C-002 [LOW] — DECLINE
- The behaviour is real but latent. ws.py probe: `private_workspace("../escaped")` returns `<base>/../escaped`.
- No caller can reach it. Every call site passes a literal (`"loa-claude-ws"` claude_headless_adapter.py:245, `"loa-gemini-ws"` gemini_headless_adapter.py:191, `"loa-agy-ws"` agy_headless_adapter.py:135). No config or request data flows into `name`.
- A basename assert would be harmless hardening, but it is not a defect today.

### d-cheval DISS-C-003 [LOW] — DECLINE
- This is by design. The fail-closed error (headless_cli.py:213-215) has to name every candidate it tried and why, because that is the only way an operator can fix "no private base". It also tells them to set XDG_RUNTIME_DIR.
- The text goes to the MODELINV ledger under `.run/`, which is gitignored (.gitignore:85), and to a2a feedback, also gitignored (.gitignore:189).
- The leaked items are the reviewer's own uid, runtime dir and home path. They carry no secret.

### d-cheval DISS-C-004 [LOW] — DECLINE
- `_TRUSTED_ABOVE` defaults to None (headless_cli.py:39). Only `monkeypatch.setattr` in tests/conftest.py:57 and test_headless_workspace.py:33,333 sets it, and monkeypatch restores it.
- No environment variable or config key reaches it.
- Code that can assign a module global in the cheval process can already do anything. That is not a trust boundary.

### e1-adapters DISS-001 [HIGH] — REAL (pre-existing; severity MEDIUM, not HIGH)
- **Input/state → outcome.** Stock config, `agy` installed and authenticated, and any Google chain reaching its CLI terminal (an HTTP failure, or cli-only/prefer-cli mode). `agy_headless_adapter.py:299-306` builds `[agy, "-p", <whole flattened prompt>, ...]`. For the life of the hop, the redacted review diff can be read by every local account through `/proc/<pid>/cmdline` and `ps` (unless /proc has hidepid).
- **Not "explicit opt-in with documentation".** The dispatch is stock: see the premise section. The exposure is documented only in the module docstring (agy_headless_adapter.py:14-21) and in bead bd-ugmi (P3, operator re-probe). There is no operator-facing text: the headless runbooks do not mention agy, and .loa.config.yaml.example describes the terminal as `gemini -p`.
- **Not a sprint-248 regression.** The argv transport came with a67a1a98 (on main), and sprint-248 only added the docstring. The prior "refuted as already documented" calls (feedback:752, 1094, 1113, 1133) rested on the false "disabled" premise. Down-rated to MEDIUM because it needs a second local account on the cheval host and no hidepid.
- **Minimal fix.** Make agy's argv transport an explicit opt-in until bd-ugmi proves a stdin path. `AgyHeadlessAdapter.complete()` raises a walkable ProviderUnavailableError before spawn unless `extra.allow_argv_prompt: true` is set on the model entry (absent from the stock default). The message names the /proc exposure. Also correct `.loa.config.yaml.example:829` and the "re-enabling agy" comments (agy_headless_adapter.py:36, :133).
- **Failing-first test** (tests/test_agy_headless_adapter.py): `test_agy_refuses_an_argv_prompt_without_the_operator_opt_in`. With `AGY_HEADLESS_BIN` pointing at a stand-in, a ModelConfig built from the stock `gemini-headless` entry (`extra={"cli_model": "Gemini 3.1 Pro (High)"}`), and `run_subprocess_pgkill` monkeypatched to record calls, assert `complete()` raises ProviderUnavailableError matching `cmdline` and the spawn recorder was never called. It is red at HEAD because the adapter spawns. A second case with `allow_argv_prompt: True` asserts one spawn.

### e1-adapters DISS-C-001 [HIGH] — REAL (narrowed; severity MEDIUM)
- **Which workspaces are stable.** `private_workspace(name)` gives one directory per name, shared by every later hop: claude `loa-claude-ws`, gemini `loa-gemini-ws` (that adapter is unreachable, see the premise section) and agy `loa-agy-ws`. codex, cursor and grok each get a fresh `tempfile.mkdtemp` per hop (codex:185, cursor:171, grok:219), held by flock and removed after the hop, so nothing persists across their hops.
- **Who can write the cwd.**
  - claude passes `--permission-mode plan --tools "" --no-session-persistence` (claude_headless_adapter.py:268-276). It has no write tool and keeps its state in ~/.claude.
  - gemini runs `--approval-mode plan`, and keeps its state in ~/.gemini.
  - agy passes `--sandbox --dangerously-skip-permissions` (agy:304-305), and the second flag auto-approves its tools. The spike (grimoires/loa/proposals/headless-adapters/agy-spike.md:20) only verified that `--sandbox` gives clean output, calling it "terminal-restricted". What it does to file writes was never probed, as the adapter itself admits at :132-133.
  - So agy is the one stable-workspace CLI that might write its cwd.
- **What the denylist stops.** ws.py probe: after planting `.env`, `.agent/`, `.antigravity/` and `.geminiignore` in `loa-agy-ws`, `private_workspace("loa-agy-ws")` still returns the path. `GEMINI.md` and a sibling `loa-claude-ws/.claude` are refused loudly. A CLAUDE.md planted at the base makes the base fall through to ~/.cache/loa (base.py), so the base is never used with it. The feedback:1203 refutation ("refuses it loudly") therefore covers only the eleven names in `_PROJECT_FILES` (headless_cli.py:43-44, 236).
- **Why that matters for agy.** gemini-lineage CLIs load `.env` from the cwd, and Antigravity's workspace rules live in a dot-directory (`.agent/`) that is not on the list. What agy loads from its cwd is unprobed, so the denylist cannot be shown complete.
- **The regression.** If agy's sandbox lets it write its cwd (the usual gemini-lineage sandbox mounts the project cwd read-write), an injected agy hop can leave a file in `loa-agy-ws` that every later agy hop loads. Round 1al's stable cwd (feedback:877) removed the per-hop containment that rounds 32-36 had. It is still strictly better than main, where agy ran in the reviewed tree itself.
- **Not refuted by the "refuse anything" objection.** Refusing any entry breaks no CLI that is known to write its cwd: claude and gemini never do under these flags. If agy turns out to write cwd state, it fails closed with a walkable ProviderUnavailableError (agy:136), which is the right outcome while bd-ugmi is open.
- **Minimal fix.** headless_cli.py:236 becomes `held = sorted(os.listdir(path))`, with the message reworded to "holds <entries> left by an earlier process — a later hop would start there: remove it". Flip the deliberate pin in tests/test_headless_workspace.py:173-174 (`notes.txt ... is no hazard`) to `pytest.raises`. Possible alternative: put agy back on a per-hop mkdtemp + hold + sweep like codex. The stable cwd was justified by an unprobed folder-trust concern, but the emptiness check is the smaller change and covers claude too.
- **Failing-first test (verified).** `test_the_stable_workspace_refuses_any_entry_a_hop_left`, parametrised over `.env`, `.agent`, `.geminiignore` and `rules.md`: plant the entry in `private_workspace("loa-agy-ws")`, then assert `pytest.raises(OSError, match="holds")`. Probe run: 4 failed at HEAD. On a patched copy of the adapters tree it gives 4 passed. With the existing workspace, agy and claude suites on that copy, 103 passed and 1 failed, the failure being exactly the notes.txt pin.
- **Rest of the claim.** Writing into the sibling `../loa-claude-ws/.claude` is already refused (probe). If agy's sandbox does not confine writes at all, the workspace is moot (it could write ~/.claude), and that is bd-ugmi's gate, not this fix.

### e1-adapters DISS-C-002 [MEDIUM] — REPEAT
- It is the same claim as e1 DISS-001 in this run (agy's argv prompt readable through /proc). Its earlier occurrences are feedback-round-1 lines 752, 1094, 1113 and 1133.
- The verdict and fix are carried under DISS-001 above. Not counted separately.

### e1-adapters DISS-C-003 [LOW] — DECLINE
- This is the same class as d DISS-C-003. grok:226-229 appends `{exc}` on purpose, so the refusal's reason reaches the operator (thirty-third run, d DISS-C-004). agy:157 and :182 name the stable workspace path so a vanished or unenterable cwd is not misread as an oversized diff (thirty-ninth run, e1 DISS-C-003).
- These are host-local paths of the reviewer's own account. The ledgers are gitignored.

### e1-adapters DISS-C-004 [LOW] — REFUTED (also REPEAT of feedback:1204)
- `sweep_stale_hop_workspaces` only removes directories whose mtime is older than `_STALE_HOP_SECONDS = 86400` (headless_cli.py:245, :313). A directory that mkdtemp created moments earlier has mtime = now, so no concurrent sweep can take it, whether or not it is held yet.
- The hold is a second guard, against a long-lived hop's directory aging past a day. The race the finding describes cannot happen.

### e1b DISS-C-001 [MEDIUM] — DECLINE
- `GeminiHeadlessAdapter` is not in `_ADAPTER_REGISTRY` (providers/__init__.py:48-59, "kept for reference"), and `gemini-headless` dispatches to agy. No cheval path reaches the `GEMINI_SANDBOX=false` injection at gemini_headless_adapter.py:159-162.
- The trade is documented in the module doc (:25-31) and was acted on in run 34 (feedback:837). An operator sandbox folds the stdin prompt into argv, so the adapter picks the transport that keeps the prompt off argv, and an explicit `--sandbox` in `gemini_extra_flags` keeps one, with a warning.
- A WARNING when an ambient sandbox is overridden would be cosmetic, on code that is never dispatched.

### e1b DISS-C-002 [LOW] — DECLINE
- The adapter is unreachable, as in e1b DISS-C-001.
- The yargs reading is a documented design choice (feedback:853, 877), and the case where an ambient GEMINI_SANDBOX contradicts `--sandbox` is refuted-documented at feedback:1206.
- Turning sandbox flags into a ConfigError would remove a supported operator choice from code that never runs.

### e1b DISS-C-003 [LOW] — DECLINE
- This is the same class as d DISS-C-003 and e1 DISS-C-003. codex's workspace and spawn messages carry the operator's own path on purpose, so a typed spawn failure can be diagnosed (feedback:908, d DISS-C-002).
- They go only to host-local, gitignored ledgers.

### e1b DISS-C-004 [LOW] — REPEAT (feedback:1205)
- `hold_hop_workspace` (headless_cli.py:248-262) catches ImportError and OSError around both the open and the flock and returns None. Its docstring says "Never raises".
- Nothing between cursor's mkdtemp (:171) and `try:` (:174) can raise, so the workspace cannot leak there.

---

| Verdict | Count | Findings |
|---|---|---|
| REAL | 2 | e1 DISS-001 (agy argv prompt, default-reachable, pre-existing), e1 DISS-C-001 (stable agy workspace guarded by a denylist only) |
| REAL-DOC | 0 | (incidental, under DISS-001: "agy disabled" at agy_headless_adapter.py:36,133 and feedback:1094/1112/1138; `.loa.config.yaml.example:829` says `gemini -p`) |
| REFUTED | 1 | e1 DISS-C-004 |
| REPEAT | 2 | e1 DISS-C-002, e1b DISS-C-004 |
| DECLINE | 8 | d DISS-C-001..004, e1 DISS-C-003, e1b DISS-C-001..003 |
| **Total** | **13** | |

<!-- group g6 -->
# g6 verdicts — sprint-248 audit, chunks e2a / e2b / e2c / e3 / e4 (HEAD 9fabac05)

Prior triage: `grimoires/loa/a2a/sprint-248/engineer-feedback-round-1.md` (cited as FB:<line>). Probes: `~/.cache/loa/cycle-126-dissent/probe-g6/` (a copy of the ledger only).

### e2a DISS-001 [HIGH] — REPEAT (DECLINE as a defect)
- CHANGELOG.md:14 is accurate: "agy's is the one argv prompt by default; gemini's is one too when gemini_extra_flags asks for a sandbox — warned of, and refused over 124 KiB". It does not say gemini goes back to argv by itself.
- Gemini never goes back to argv without being asked: `gemini_headless*.py:161-162` sets `GEMINI_SANDBOX=false` unless `_asks_sandbox(command[1:])`, so an ambient `GEMINI_SANDBOX` or `tools.sandbox` is overridden. Argv happens only when the operator puts `-s/--sandbox` in `gemini_extra_flags` (:179-189: WARN naming /proc/<pid>/cmdline, refused over 128 KiB−4 KiB). No `gemini_extra_flags` is set in `.loa.config.yaml`. The Flatline tertiary (gemini) is disabled (`.loa.config.yaml:340-345`).
- agy is a known, accepted, documented exposure. It has no stdin or file transport, its stdin must stay closed, and its module docstring (agy_headless:12-19) states the risk. agy is not installed and is disabled, and the operator re-probe is bead bd-ugmi (open).
- Same claim already refuted: FB:1072, FB:1094, FB:1113, FB:1116, FB:1133. The gemini-sandbox half was fixed and documented at FB:837 and FB:896.

### e2a DISS-C-001 [LOW] — REPEAT
- The same residual as e2a DISS-001. The finding itself calls it "a documented residual rather than a verified defect". See FB:1094, FB:1113, FB:1133 and bd-ugmi. Gemini argv happens only on an explicit operator `--sandbox` (above).

### e2b DISS-C-001 [MEDIUM] — REPEAT
- The `.loa.config.yaml` comments at the run_bridge `claude-headless` entry and above `flatline_protocol.models.primary` already say: "the route — and the account billed — is the environment's, not this file's: a shell without CLAUDE_HEADLESS_BIN (cron, CI, a fresh login) runs Flatline and Bridgebuilder on the plain CLI's plan … export the wrapper in every shell".
- This was acted on as docs in run 39 (FB:911, "the Flatline comment names the route, bucket and breaker reset (e2b DISS-C-002/003)"). The switch was made on the operator's directive of 2026-10-01. The spiral-side gap is tracked as bd-swz7 (P1, open).
- No `compliance_profile` is configured in `.loa.config.yaml`, so no configured compliance boundary is being bypassed.

### e2b DISS-C-002 [MEDIUM] — REPEAT
- `auditing-security/resources/BEADS-WORKFLOW.md` already says: "A re-review or re-audit adds its round's label and `br label add` never removes the other, so a task can carry both: the latest `SECURITY AUDIT:` comment is the verdict of record (with the feedback file and the COMPLETED marker), a label only history". The reviewing-code twin says the same.
- This was decided and written in run 39 (FB:911, "both BEADS-WORKFLOW resources say the verdict labels accumulate and the latest comment is the verdict of record"; CMP-272).
- No consumer reads label presence. A grep of `.claude/` for `security-approved` finds only the docs (beads-integration.md:149, audit-sprint.md:239, this resource). The skill's allowlist grants `br label add` only, so `label remove` is outside the skill's tool grant by design.

### e2b DISS-C-003 [MEDIUM] — DECLINE (pre-existing, out of scope)
- In this sprint, `git diff main...HEAD -- .claude/rules/skill-invariants.md` changes only the row's "Why" text. The `disallowed-tools: [NotebookEdit]` of reviewing-code and auditing-security is the same on main (`git show main:.claude/skills/reviewing-code/SKILL.md`).
- Neither skill's `allowed-tools` grants any git mutation (review: `git diff *`, `git log *` only), so a `git commit` from inside those skills is not pre-approved.
- Hardening the review skills with `Bash(git add/commit/push *)` is a reasonable cycle-end bead. It is not a defect this diff introduced.

### e2b DISS-C-004 [MEDIUM] — REPEAT
- The shared-breaker single-voice consequence is documented in the Flatline comment (run 37, FB:880). The audit gate does not fail open on it: `auditing-security/resources/ADVERSARIAL-REVIEW.md:40-44` says "a completed run is still a degraded audit when its second voice is missing: `companion_voice.status` `failed` … set the `DEGRADED_SECURITY_REVIEW` marker".
- Making that marker a mechanical check was already deferred as a cycle-end bead (FB:1087). The shared breaker and per-binary lock are KF-037's routed structural residue (FB:1161).

### e2b DISS-C-005 [LOW] — REPEAT
- Budget caps for Fable: refuted as decided at FB:1155 and deferred to the operator at FB:1187 (the third raise). The config comment at spiral.harness states the cost multiple and the (1 + max_phase_retries)× retry spend.
- `executor_model`/`advisor_model: fable` comes from the operator directive of 2026-10-01, written into the config comment. The cross-family voice comes from the dissent companion by design.

### e2b DISS-C-006 [LOW] — REFUTED
- `.gitignore:189` is `grimoires/loa/a2a/*`, with exceptions only for README, trajectory/README and compound/.gitkeep.
- `git check-ignore -v` reports both `grimoires/loa/a2a/sprint-9/auditor-sprint-feedback.md` and `grimoires/loa/a2a/audits/x/findings.jsonl` as ignored by that rule. The feedback files are not committed, so the BEADS-WORKFLOW rationale is accurate.

### e2c DISS-C-001 [MEDIUM] — REAL (LOW; pre-existing class, reachable through the sprint's new gate)
- `san1` (kf-write-lib.sh:52, unchanged from main) strips only C0 bytes under LC_ALL=C. The python gate (:86) refuses No/Cf/Cn but not Zl, Zp or Cc, so U+2028, U+2029 and U+0085 reach the heading line.
- The canonical reader `kf-auto-link.py:215` `parse_known_failures` splits with `str.splitlines()`, which treats those characters as line breaks.
- Probe (on a copy): `new --file kf.md --title $'probe ls ## KF-001: phantom' --status OPEN` → rc 0, KF-040 written. `parse_known_failures(copy)` → `ValueError: malformed KF entry 'KF-040' at line 1624: Status field is empty or missing`. The original ledger parses (39 entries). One write makes the whole ledger unparseable for the canonical reader, and verify_and_swap's grep checks stay green.
- Minimal fix: in `san1`, map the UTF-8 sequences `\xc2\x85` and `\xe2\x80\xa8`/`\xe2\x80\xa9` (and the C1 range `\xc2[\x80-\x9f]`) to a space. This covers title, symptom, reading-guide, note and every cell. Optionally also exit 4 on Cc/Zl/Zp in the gate.
- Failing-first test (kf-write-lib.bats): write a title with U+2028 plus `## KF-001: x`. Assert that no line of the file holds `\xe2\x80\xa8`, and that `python3 -c 'parse_known_failures(...)'` succeeds with the same entry count + 1.

### e2c DISS-C-002 [MEDIUM] — DECLINE (pre-existing, outside the helper's contract)
- `--reading-guide` (:213) and `--note` (:296) pass through the same `san1` as on main (the diff touches neither line).
- The header states the helper "enforces ONLY that floor — non-empty id/Status, and a non-empty Evidence cell … and leaves everything else free-text". The writer is a trusted agent or operator, and the ledger is reviewed in the diff like any other file.
- The canonical reader and verify_and_swap are unaffected: a `<!--` hides content only in GitHub's rendering. Teaching the link lint about HTML blocks is optional hardening, not a sprint defect.

### e3 DISS-C-001 [LOW] — REPEAT
- Refuted three times already: FB:1157 (the comment claims only the CLI lock; no suite reaches a real CLI), FB:1174 (`_adv_cli_lock_dir` uses XDG_RUNTIME_DIR verbatim with no mode check, so there is no fallback to a shared path) and FB:1210 (the runtime base is used first and is ours inside BATS_TEST_TMPDIR).

### e4 DISS-C-001 [MEDIUM] — DECLINE (by design; existing precedent)
- The config comes from the operator's own `.loa.config.yaml` via `yq` (config.ts:87-114). That is the same file that already picks BB's primary model.
- The single-model path has dispatched a `*-headless` model with no API key since cycle-109 #880 (`adapters/index.ts:34-53`, `isHeadlessModel`). The multi-model change (thirty-seventh run, FB:878) brings the key gate in line with that path.
- A headless entry needs no key, so strict mode correctly finds no missing key. The opt-in is the operator naming a headless id, per the 2026-10-01 directive.

### e4 DISS-C-002 [LOW] — REFUTED (REPEAT)
- `adapters/adapter-factory.ts:46-53`: `createAdapter` builds `ChevalDelegateAdapter({model, timeoutMs, agent, mockFixtureDir})`. `apiKey` is never forwarded, so nothing can be exported to the child.
- Refuted twice before: FB:1186 and FB:1211.

### e4 DISS-C-003 [LOW] — DECLINE
- The finding concedes that both callers pass the provider (config.ts:167, multi-model-pipeline.ts:188). The one-argument form is used on purpose by the registry and case tests (multi-model-config.test.ts:162-167), and the provider check was added deliberately in run 39 (FB:910).
- This is a style preference with no reachable bypass.

## Counts

| Verdict | Count | Findings |
|---|---|---|
| REAL | 1 | e2c DISS-C-001 |
| REAL-DOC | 0 | — |
| REFUTED | 2 | e2b DISS-C-006, e4 DISS-C-002 |
| REPEAT | 7 | e2a DISS-001 (HIGH), e2a DISS-C-001, e2b DISS-C-001, e2b DISS-C-002, e2b DISS-C-004, e2b DISS-C-005, e3 DISS-C-001 |
| DECLINE | 4 | e2b DISS-C-003, e2c DISS-C-002, e4 DISS-C-001, e4 DISS-C-003 |
| Total | 14 | |
