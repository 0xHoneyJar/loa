## ELI5 (draft; replication numbers pending)

We asked: when Loa's full review pipeline finds more planted bugs than one plain model, which part of the pipeline is doing the work, and is the measurement fair?

**What we found.** The headline gap was +26 points, all of it on one of four pull requests. About half of that gap is a ruler problem, not a review problem: the grader only counts a catch if the reviewer's line number lands within three lines of a label, and the plain model writes one line per bug while the pipeline writes several. Re-measured by "is the citation in the right function", the gap is about +14 points. A second slice is a leak: the pipeline's sandbox carried a newer copy of the same code with the bugs already fixed, and in one of twelve runs the reviewer diffed against it and copied the answers. Remove that run and the gap is +23 points by the old ruler, roughly +11 by the fair one.

**Who found the extra bugs.** Not the second-opinion models. Their findings never carry line numbers, so they are never credited, and in the transcripts they named only about two bugs the main reviewer had not already written down. The extra catches come from the main reviewer writing a concerns list first, running the tests, and a second reading by the audit gate. That costs 17 times the plain model.

**Are the "false alarms" false?** Mostly not. Two independent graders found almost no wrong claims; most "false alarms" are cross-references the counter should not have counted, and many are real bugs the answer key missed. The plain model is right about 44 % of what it flags, the pipeline 16 %.

**Replication.** @@REPLICATION@@

**What to change.** Fix the leak, fix the ruler, and only then decide what the dissent and the audit gate are worth.
