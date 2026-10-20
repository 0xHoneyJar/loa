# Task 1.10 adjudication result — 2026-10-19T07:38:41Z

Pre-registration: grimoires/loa/NOTES.md 2026-10-19T06:08:48Z. Pool from the grader-1.3.0 re-grade (`regrade-c131.md`): (a) credits_function_only = 7 (run, defect) pairs over the 36 runs (all taken; 20 planned), (b) anchor-expansion-only credits = 40 (10 sampled, stratified arm × PR, seed 20261015). Builder `build_packets.py`; labelers: two Opus 5.5 subagents (labeler-L1, labeler-L2) with `labeler-prompt.md` + `launch-prompt.md`; reader `adjudicate.py`. Clarification recorded in NOTES: the human finding text came from each defect's `source` (record branch) and, for the synthetic pr-08 packet, from the planted defect's id/category/line.

```
packets 17 (a=7, b=10); labelers labels-L1.tsv vs labels-L2.tsv: agreement 1.000, Cohen's kappa 1.000
disagreements: none
final labels = agreements (disagreements pending)
group (a): n=7, labelled=2, different=5, unclear=0, pending=0; share 0.286 Wilson95 [0.082, 0.641]
adoption rule (>= 80 % of (a) labelled): NOT adopted (recall_pm3 becomes the decision statistic); kappa floor 0.6 met
group (b): n=10, labelled=6, different=4, unclear=0, pending=0; share 0.600 Wilson95 [0.313, 0.832]

per packet: id group L1 L2 final
P01 a labelled labelled labelled
P02 b different different different
P03 a different different different
P04 a different different different
P05 b labelled labelled labelled
P06 a different different different
P07 b labelled labelled labelled
P08 a different different different
P09 b labelled labelled labelled
P10 a labelled labelled labelled
P11 b different different different
P12 b labelled labelled labelled
P13 b different different different
P14 a different different different
P15 b different different different
P16 b labelled labelled labelled
P17 b labelled labelled labelled
```

## Key (un-blinded after labelling)

| packet | group | arm | PR | defect | sites (curated) | sites (v1) | L1 | L2 |
|---|---|---|---|---|---|---|---|---|
| P01 | a | a1_full | pr-12 | d8 | [26, 63, 72, 79, 85] | [26, 63] | labelled | labelled |
| P02 | b | a0_bare | pr-12 | d7 | [487, 502, 503] | [487] | different | different |
| P03 | a | a0_bare | pr-13 | d4 | [17, 39] | [39] | different | different |
| P04 | a | a0_bare | pr-18 | d7 | [869, 871, 875, 890, 897] | [869] | different | different |
| P05 | b | a0_bare | pr-17 | d10 | [57, 66, 71, 72] | [66] | labelled | labelled |
| P06 | a | a0_bare | pr-17 | d2 | [369, 373, 398, 402, 408, 414, 435] | [369, 373, 414] | different | different |
| P07 | b | a0_bare | pr-12 | d1 | [131, 137] | [131] | labelled | labelled |
| P08 | a | a0_bare | pr-13 | d4 | [17, 39] | [39] | different | different |
| P09 | b | a1_full | pr-12 | d7 | [487, 502, 503] | [487] | labelled | labelled |
| P10 | a | a0_bare | pr-08 | d3 | [164] | [164] | labelled | labelled |
| P11 | b | a0_bare | pr-13 | d5 | [42, 71, 136, 162] | [42, 71, 136] | different | different |
| P12 | b | a0_bare | pr-12 | d7 | [487, 502, 503] | [487] | labelled | labelled |
| P13 | b | a1_full | pr-17 | d9 | [821, 839, 841, 846, 869, 870, 871] | [821, 841, 846] | different | different |
| P14 | a | a1_full | pr-13 | d4 | [17, 39] | [39] | different | different |
| P15 | b | a0_bare | pr-17 | d6 | [637, 642, 651, 653, 655, 657, 691] | [637] | different | different |
| P16 | b | a1_full | pr-18 | d2 | [100, 105, 124, 131, 148, 183] | [131, 148, 183] | labelled | labelled |
| P17 | b | a0_bare | pr-17 | d8 | [42, 57, 62, 71, 72, 76] | [42, 57, 62] | labelled | labelled |

## Labeler reasons

- **P01** L1: Stub :92 encodes exit codes the test author chose, not cheval's EXIT_CODES; matches the label's taxonomy bullet (C-006), not its setup-vocabulary bullet  
  L2: Finding says the test stub's exit codes (quota -> 6) are author-chosen and mismatch cheval EXIT_CODES; same as the label's C-006 taxonomy bullet
- **P02** L1: Finding is dotenv precedence and quote/comment strip order causing false presence; label is the secret materialised in val under xtrace  
  L2: Finding is about dotenv precedence and quote/comment stripping giving a false "present"; label is the secret materialised in val under xtrace
- **P03** L1: Finding is the 200K-1M range missing from the class table; label is the >1000-line edge case not class-scoped  
  L2: Finding is the unhandled 200K-1M context-window range; label is the >1000-line edge case contradicting the long full-file row
- **P04** L1: Finding is /^###/ also matching #### headings; label is the fence toggle (not md-fence.awk) and fail-open Date gate  
  L2: Finding is /^###/ matching #### headings; label is the hand-rolled fence toggle and the Date gate failing open
- **P05** L1: Finding: porcelain compare misses writes to shared git dir (refs, config, hooks), helper exits 0; that is the label's main-tree-only boundary  
  L2: Finding says the porcelain compare misses writes to the shared git dir (hooks, refs, config) so the probe exits 0; that is the label's boundary defect
- **P06** L1: Findings are handoff glob prefix collision and handoff accepting proposed rows; label is op_close --consumed-by not verifying handed-off/open rows  
  L2: Findings are the report-glob prefix collision and handoff accepting proposed rows; label is op_close --consumed-by not requiring handed-off status
- **P07** L1: Same defect: contract check only greps the heading; empty or partial triage passes; count list items vs rejected_summary length  
  L2: Finding says the check only greps the heading, so an empty or partial section passes, and asks for an item count vs rejected_summary length
- **P08** L1: Finding is loa-status display_context_line placement/JSON omission; label is the >1000-line edge case contradicting the long row  
  L2: Finding is loa-status.sh not printing the context class outside one branch; label is the class-unscoped large-file edge case
- **P09** L1: Auditor LOW-001 describes val holding the dotenv secret and xtrace leaking it; same mechanism and fix as label bullet one  
  L2: Auditor finding says _adv_cred_present reads the secret into val and xtrace would leak it; matches the label's first bullet
- **P10** L1: Finding: removed except ValueError lets an embedded-NUL prompt escape raw instead of ProviderUnavailableError; matches the planted defect  
  L2: Finding says the removed except ValueError lets an embedded-NUL prompt escape as a raw ValueError; that is the planted defect
- **P11** L1: Finding laments lost numeric tiers and unseen REFERENCE table; label is parallel_threshold being unitless and misaligned, not a lost guard  
  L2: Finding: numeric tiers removed so splitting is not reproducible; label: parallel_threshold has no unit or reader and disagrees with the tables
- **P12** L1: Finding: grep/sed extract the credential into val before the emptiness test, contradicting never-read; presence-only grep -q fix; label bullet one  
  L2: Finding says _adv_cred_present reads the credential into val, contradicting "never read", and proposes grep -q; matches the label first bullet
- **P13** L1: Findings are fence bypasses (refspec push, branch -f, update-ref); label is a false-positive block of prose lines via [^;&|]*  
  L2: Findings are bypasses (refspec push, branch -f, update-ref allowed); label is an over-broad merge span blocking prose lines, a false positive
- **P14** L1: All three findings are the >200K column label/400K models; label is the >1000-line edge case not class-scoped  
  L2: Findings are about the long column label vs 400K models; label is the large-file edge case contradicting the long full-file row
- **P15** L1: Finding is spike delete not checking the branch was pushed; label is the missing positive/forged-transition test coverage  
  L2: Finding says the delete does not check the spike was pushed (data loss); label is missing tests for the decided-row and forged-transition cases
- **P16** L1: Same defect: an _Aliases_ line before the first term has empty entry, tokens read MISS misleadingly; fix skip with WARN  
  L2: Findings say an _Aliases_ line before any term has an empty entry and reads MISS with a misleading message; matches the label
- **P17** L1: Same mechanism at same site: porcelain line unchanged when an already-listed file's content changes; label names the ignored .run/.beads case  
  L2: Finding says the porcelain compare misses content changes to files whose status line stays the same; same mechanism as label (ignored .run/.beads)

## Outcome

Same-scope rule NOT adopted (DEC-0638): `recall_pm3` is the decision statistic for Sprint 264 pre-registrations and Sprint 265 reads; `recall` and `recall_pm3_v1` reported beside it. Group (b) share 0.600 [0.313, 0.832] carried as a labelled caveat on the curated anchors.
