VERDICT: APPROVE

Findings
- (none blocking) No CRITICAL/HIGH/MEDIUM findings.
- LOW/informational .claude/scripts/loa-status.sh:898 — the prime runs inside the `$(get_providers_json)` subshells (callers at :621 and :915), so the memo lives only in that subshell and its children; correct by construction, and the comment at :823-825 ("the subshells inherit the answer") describes this accurately. Not exported (no `export` of the name; grep of .claude/ and tests/ finds _LOA_STATUS_AGY_OPT only in loa-status.sh), no name collision.
- Check 1(a): prime calls the real `agy_opted_in "$(_providers_config_file)"` — same path expression the fallback at :827 and agy_gate_warn_once at :914 use. 1(b): only callers of `_agy_opted_in` are _provider_hop_note (:832) and _provider_hop (:837), both reached only inside get_providers_json's loop, after the prime; no caller passes a different path. agy_opted_in is side-effect free (stderr suppressed in _agy_opt_in_node), so the extra unconditional prime call cannot change output. agy_gate_warn_once still calls agy_opted_in directly (unchanged). 1(c): missing-lib stub `agy_opted_in(){ return 1; }` → memo 1 → same "off" semantics as before (reasoned, not executed). 1(d): not exported, no collision.
- One lever: yes (single memo of one predicate). Comments accurate. bash -n OK. Mirrors verified: old == HEAD, new == live.

parity 7/7 configs x 2 modes = 14/14 PASS (stdout normalised + stderr + rc): live, opt_in true, false, "true" (string), absent, PATH=/tmp/eso14-noyq with live config, PATH-no-yq with opt_in true. Fixture sanity: --json google cli_hop_note null under true, "agy: opt-in (disabled; ...)" under false; string "true" emits the extra WARN identically in both. Symlinks restored (verified).
bats: loa-status-providers + agy-gate-conformance + flatline-tertiary-agy-opt-in 44/44 ok, 0 not ok.
hyperfine (-N -i, warmup 2, 8 runs): old 653.9 ± 24.8 ms -> new 631.8 ± 27.3 ms (-3.4%); within-noise overlap but consistent with orchestrator's 670.8 -> 637.0.
UNVERIFIED: missing agy-gate-lib.sh stub path not executed (mirror lib dir would require altering a shared tree); --help/--bogus not re-run (orchestrator covered).
