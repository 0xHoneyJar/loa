# Glossary: Loa framework

The shared language of the Loa agent framework, for humans and agents. It is mounted into every project with the framework and defines what each word means in day-to-day work; the mythic background of the names lives in the lore, and a project's own terms belong in that project's root glossary, never here.

## Language

**Beads**: The local-first task tracker, driven through its br command, that is the single source of truth for sprint tasks, decision tickets and their dependencies.
_Aliases_: br

**Bridgebuilder**: The automated pull-request reviewer that posts findings on a pull request and drives the iterative improvement loop of a bridge run.

**Cheval**: The model-dispatch substrate through which every call to an external model provider is routed, with fallback, budget limits and cost accounting.

**Circuit breaker**: The run-mode guard that halts a run after repeated identical findings, no progress, a cycle limit or a timeout, leaving the run for the operator to resume.

**Construct**: An installable package of skills, personas and grimoire paths that extends the framework for a domain and may declare its own workflow gates.

**DEC row**: One entry of the decision ledger, numbered DEC-NNNN, recording a decision, its alternatives, its status and the voice that proposed or decided it.
_Avoid_: ADR, decision note

**Decision ticket**: A question-type bead under a map epic whose resolution is a decision, not a build slice.
_Avoid_: question task

**decision:grilling**: The label of a decision ticket that talking can settle, answered in interview rounds with the operator.

**decision:prototype**: The label of a decision ticket the operator needs to see before answering, settled by a spike and its verdict.

**decision:research**: The label of a decision ticket that needs reading or sources, answered by a read-only research report and one confirming round.

**decision:unblock**: The label of a decision ticket that a read-only probe settles by showing whether a suspected blocker is real; it never builds anything.

**Dissent**: A second model's independent review of the same diff, triaged before a gate verdict.
_Avoid_: second opinion, cross-check

**Flatline**: The multi-model adversarial review of planning documents, in which independent voices review and cross-score each other before findings are integrated.
_Aliases_: Flatline Protocol

**Fog of war**: Decisions an effort can tell are coming but cannot yet phrase sharply; a map keeps them under Not yet specified.

**Frontier**: The open, unblocked, unclaimed decision tickets of a map; in an interview, the questions whose prerequisites are already settled.

**Golden path**: The five everyday commands (loa, plan, build, review and ship) that detect where the workflow stands and route to the right truename.

**Grimoire**: The project's state area of planning documents, notes, reviews and records that agents read and write across sessions.

**ICE**: Intrusion Countermeasures Electronics, the git safety layer of run mode that owns branch creation, push decisions and the refusal to touch protected branches.

**Implement gate**: The hook that asks before an edit to application code made outside the implement or bug workflows.

**Jack in**: To start an autonomous run under run mode; a run that has finished or been stopped for good has jacked out.
_Aliases_: jack out

**Kaironic**: Stopping at the right moment rather than after a fixed count: an iterative review loop ends when successive passes stop finding material issues.
_Avoid_: converged

**Karpathy principles**: The four working rules applied on every code-touching turn: think before coding, simplicity first, surgical changes and goal-driven verification.

**Known failure**: A recorded degradation with its symptom, the attempts made and a reading guide, consulted before triage so that prior dead ends are not retried.
_Aliases_: KF

**Lore**: The mythic and narrative background of the framework's names, kept apart from this glossary, which defines only working meanings.

**Map epic**: The epic bead that parents an effort's decision tickets, paired with a map document of its destination, decisions so far, fog and exclusions; run mode never implements it.

**Round**: One frontier of interview questions asked together and answered together.

**Run mode**: Unattended execution of a sprint plan with a circuit breaker, wrapping implement, review and audit in a loop. Its states are running, halted and jacked out.
_Aliases_: RUNNING, HALTED, JACKED_OUT

**Seam**: A point where a test observes the system, declared in a sprint plan together with what it catches, what it misses and its prior art.

**Spike**: A throwaway prototype on its own branch that answers one decision ticket; only its report and its verdict row reach the working branch.

**Truename**: The underlying command that a golden-path command routes to, used directly by power users.

**Verdict trailer**: The machine-readable last line of a review or audit feedback document, which must agree with its findings. Any critical or high finding forces a changes-required verdict.
_Aliases_: LOA-VERDICT

**Voice**: The party a decision or finding is attributed to: the operator, the agent, Flatline or dissent.

**Zone**: One of the three permission regions of a repository: the System zone holds the framework and is never edited by hand, the State zone is read and written freely, and the App zone needs confirmation before a write.
