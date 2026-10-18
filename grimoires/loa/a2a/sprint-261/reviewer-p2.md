# Sprint 261 fix implementer P2: codex pre-flight refinements (DISS-C-001, DISS-C-002, DISS-C-003)

Worktree `/home/merlin/Documents/thj/code/loa-wt-s4p2` at `ff7fb403`. Files touched: `evals/harness/run-ablation.sh`, `evals/tests/run-ablation.bats` (plus this report copy).

## What was built (file:line, worktree)
- **DISS-C-001 horizon lower bound**: `evals/harness/run-ablation.sh:873-875`. `required_until = now + 2 x max(S / concurrency, W)`, S the sum and W the largest `watchdog_s` over the counted trials (empty set: 0). The refusal text (`:913`) names the rule: `now + 2 x max(summed watchdog of <n> trial(s) / concurrency, longest watchdog)`. Header pre-flight 6 paragraph `:115-138`.
- **DISS-C-002 no scratch-file dependency**: `CODEX_PF_JSON=null` default at `:339` (set right after the env knobs, before any pre-flight); pre-flight 6 sets it at `:920` from the python output (no `$WORK/codex-preflight.json` any more). `write_manifest` (`:950`, `codex_token_exp: ($cpf // {}).token_exp, codex_preflight: $cpf`) and `write_status` (`:1161`, `codex_preflight: $cpf`) take `--argjson cpf "$CODEX_PF_JSON"`. Header field notes for MANIFEST and STATUS updated (STATUS: null if written before pre-flight 6 ran).
- **DISS-C-003 rerun_pending counted**: scope JSON gains `status: <batch>/STATUS.json` (`:822`); `pending()` (`:846`) reads `rerun_pending` (strings only; a missing/malformed file or a non-list is the empty set); `remaining()` (`:864`) adds `pending() - rerow_ids`. The header documents the divergences.

## Horizon rule and codex_preflight shape as built
- `required_until = ceil(now + 2 x max(sum(w) / max(concurrency, 1), max(w)))`; override unchanged: `now + LOA_ABLATION_CODEX_HORIZON_S`.
- `codex_preflight` shape unchanged: `{checked, auth_file_present, codex_arms, token_exp, required_until, auth_mode, trials_counted, horizon_source}`; MANIFEST and STATUS both receive it from `CODEX_PF_JSON` (JSON `null` before pre-flight 6).

## write_status call sites checked (and ordering)
`write_status` is defined at `:1143`, after pre-flight 6 (`:920`), and bash cannot call a function before its definition, so no call site can run before `CODEX_PF_JSON` is set. Sites:
1. `:1373` collect(), early-return path (after the job files are removed).
2. `:1414` end of collect().
3. `:1464` on_signal() (trap armed at `:1609`, after the first write at `:1608`; SIGTERM before that point takes the default action and writes no STATUS).
4. `:1469` finish(), then `exit`; the EXIT trap `cleanup` (`:1176`, armed `:1186`) removes `$WORK` after it.
5. `:1608` the first write before dispatch (after resume reconciliation, `--clear-drift` and `--rerow`).
6. `:1621` budget cut in the dispatch loop.
- `rerow_all` updates STATUS.json `.rerowed` by jq directly (not write_status); it reads only STATUS.json.
- The `--clear-drift` path writes nothing before the lock (it builds `CLEAR_PENDING` only); `refuse`/`die` never write STATUS.
- The reachable failure was `$WORK` vanishing before a later write (a tmp reaper, or a signal landing after cleanup started): jq `--slurpfile` failed, `set -e` killed the handler, STATUS stayed `running`. RAB-40 reproduces it.

## Tests (evals/tests/run-ablation.bats)
- RAB-39 (`:1058`) DISS-C-001: one trial (watchdog 16,800 s) at concurrency 3, token now + 22,400 s: refused with the new rule text, no MANIFEST; token now + 34,200 s passes, required_until about now + 33,600 s. Fails before (exit 0, not 2), passes after.
- RAB-40 (`:1075`) DISS-C-002: a detached driver with a hanging stub; its scratch dir under a test TMPDIR is deleted, then SIGTERM. STATUS.json is valid JSON, `state partial`, `signalled true`, `codex_preflight` equal to MANIFEST's, no `.tmp` left. Fails before (state stays `running`), passes after.
- RAB-41 (`:1099`) DISS-C-003: a complete two-trial batch, STATUS `rerun_pending` planted with one id: `--resume` records `trials_counted 1`; with `--rerow` of that id: 0; a non-list `rerun_pending`: ignored, 0. Fails before (0, not 1), passes after.
- Literals changed: RAB-28 refusal text now `(now + 2 x max(summed watchdog of 1 trial(s) / concurrency, longest watchdog); KF-048)`; RAB-30 expected horizon 33,600 s (was 17,600 s, i.e. the bug: (9600 + 16800) / 3 < 16800) and its comment. RAB-31 and RAB-37 needed no change (RAB-37 runs at concurrency 1, where the sum dominates).

## bats counts
- `evals/tests/run-ablation.bats`: 39/39 before, 42/42 after.
- `evals/tests/` whole: 423/423 before (brief, at HEAD), 426/426 after (bats exit 0).

## DECISION bullets
- DECISION: the lower bound is the single largest watchdog W of the counted set (not W of the last-dispatched trial): the batch's critical path is at least its longest trial whatever the order.
- DECISION: an empty counted set (everything rowed) gives required_until = now; a token valid now passes, as before.
- DECISION: rerun_pending ids are counted even though this launcher does not relaunch them unless flagged again (the id keeps its old row and joins the done set). The count is a documented superset; it can only lengthen the horizon (refuse more), the safe direction. Making the launcher re-flag rerun_pending is a launcher behaviour change outside this brief.
- DECISION: a malformed STATUS.json or a non-list rerun_pending counts nothing extra rather than failing the pre-flight; the resume's own STATUS.json reads report a broken file.
- DECISION: last-row-wins in remaining() is kept; a duplicated run_id is refused by the launcher's reconciliation after the pre-flight, so the only effect is which status the pre-flight reads for an already-doomed resume (documented in the header).
- DECISION: no test drives write_status before pre-flight 6, because no such path exists (the function is defined after it; the signal trap is armed later still). RAB-40 drives the reachable variant (a write after $WORK is gone); the `null` default is defensive and documented.
- DECISION: RAB-40 deletes the scratch dir with `find -mindepth 1 -delete` under a test-owned TMPDIR (the repo's destructive-bash hook rejects `rm -rf` on a glob).

## Could not do / limitations
- No call path exercises `codex_preflight: null` in STATUS.json; see the DECISION above.
- `write_manifest` still uses `$WORK` for gate/delta/plan/suite/tasks files it writes or reads itself; those are in-process and present whenever it runs (the dry run and the fresh start, both before the EXIT trap).

## Handoff notes for the lead
- Patch: `~/.cache/loa/cycle-130/patches/s4-p2.patch` (+ `.stat`), made with `git add -A && git diff --cached --binary` in the worktree (staged only; no commit).
