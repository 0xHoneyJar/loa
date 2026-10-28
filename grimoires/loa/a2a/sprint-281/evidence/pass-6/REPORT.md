# ESO pass 6 — loa-kf-surface.sh: single-pass sanitisation
Matrix: Impact 5 (SessionStart hook 479 ms -> 18 ms), Confidence 5, Effort 1 => 25.
Hotspot: output loop, ~750 spawns (3x _san() 4-process pipelines x 63 rows) ≈ 96% of wall time (trace 1631 lines).
Before 479.2 ± 32.2 ms; after 18.1 ± 2.8 ms (hyperfine -N, warmup 3, 10 runs, session payload). bash -x trace lines 1631 -> 316.
Change: .claude/hooks/loa-kf-surface.sh — rows awk now `LC_ALL=C awk` with san() (awk twin of _san(), 100 bytes) and emits final "  - ID (rec N): symptom" lines; read loop replaced by printf '%s\n' "$rows". Symptom leading/trailing tabs trimmed first (emulates tab-IFS read -r). Contract comments updated. _san() kept as reference twin (unused).
Locale: GNU cut 9.7 -c is byte-based in all locales; mawk is byte-based; awk pinned to LC_ALL=C so gawk would agree. Old output identical under en_AU.UTF-8 and C.
Isomorphism: ordering preserved (order[] same), tie-breaking N/A, FP N/A, hash seeds N/A. Sanitisation unchanged (control bytes, tab/CR/LF flatten, collapse, trim, 100-byte cap) — same bytes. WARNING paths and count line untouched. Exit 0 everywhere.
Golden: live file, disabled, missing file, zero entries, adversarial fixture (tabs/CR/\001/\033, runs of spaces, 150 chars, byte-100 split of 2- and 3-byte UTF-8, empty symptom, missing/non-numeric recurrence, >= prefix, duplicate id, | < >, invalid UTF-8, control bytes at cap) x {en_AU.UTF-8, C}: stdout+stderr+rc diff -r identical (20 files... all identical).
Tests: tests/unit/kf-surface.bats + tests/unit/profile-lib.bats all pass, 0 not ok.
Not fixed: NUL bytes in a symptom — old bash $(...) would warn on stderr; new awk strips silently (stdout same). loa_knob (yq/profile-lib sourcing) remains the next cost (~18 ms total).
Checked/correct: dedup by id, ≥ (UTF-8) recurrence prefix parsing, kf_count via grep -c unchanged, test-mode seam untouched.
