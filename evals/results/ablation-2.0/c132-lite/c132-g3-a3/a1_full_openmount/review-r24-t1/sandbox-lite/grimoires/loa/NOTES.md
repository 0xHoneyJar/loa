# NOTES

## Learnings
- [2026-10-23T02:39:20Z] [reviewing-code] Calibrated filter review: extract the scanner from base and head, run paired bypass probes plus controls through both; exclusion branches added to silence false positives (grader 1.2.x) hid 12 false negatives the PR tests never asserted → skills-pending/learning-20261023T023920Z-30f43f25
- [2026-10-23T02:50:00Z] [auditing-security] When a filter gains a regex over untrusted text, time it on the non-matching case (an unterminated introducer): `(?:.*?\n)*?` under re.S doubled per input line (22 lines → 1.2 s). Also check whether the caller bounds the call — run-ablation.sh invokes the grader with no timeout and its watchdog stops once the pipeline has a final record, so a grader hang stalls the batch. Audit of sprint-1 (PR sprint-260): 0 critical / 5 high / 5 medium / 11 low, CHANGES_REQUIRED; 45 paired probes, 23 head misses.
