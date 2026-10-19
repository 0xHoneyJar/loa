## ELI5

We asked: when Loa's full review pipeline finds more planted bugs than one plain model, which part does the work, and is the measurement fair?

**The original number was inflated two ways.** The grader counts a catch only if the reviewer's line number lands within three lines of a label. The plain model writes one line per bug, usually the bug's own line; the pipeline writes several, and labels sit on function headers. Measured by "is the citation in the right function", the gap falls from +26 points to +14. Separately, the pipeline's sandbox carried a newer copy of the code with the bugs already fixed; in one of twelve runs the reviewer diffed against it and copied the answers. Without that run the gap is +23, about +11 by the fair ruler.

**Who found the extra bugs.** Not the second-opinion models: their findings never carry line numbers, so they are never credited, and they named about two bugs the reviewer had not already written down. The extra catches come from a concerns list written first, running the tests, and a second read by the audit gate, at 17 times the cost.

**The "false alarms" are mostly not false.** Two independent graders found almost no wrong claims; most are cross-references the counter should not have counted, many are real bugs the answer key missed.

**Replication.** On two fresh pull requests the pipeline again caught far more (about three quarters versus one quarter), surviving both corrections. But the second-opinion models never ran there, the reviewer peeked at the newer copy in two of six runs, and the plain model is a different model, so we really compared "Fable reading twice with a checklist" against "Opus reading once".

**So:** close the peek, fix the ruler, run a bare-Fable control, then price the dissent and the audit gate.
