# Task: one enum for job statuses

`jobboard` (under `src/jobboard/`) is a small in-memory job queue with a status report. A job's status is a raw string (`"pending"`, `"running"`, `"done"`, `"failed"`). The strings are spelled, compared and listed throughout the queue (`jobboard.board`), the policy helpers (`jobboard.policy`) and the report (`jobboard.report`), so a typo in any one of them is a silent bug.

**Refactor:**
- Add a module `jobboard.status` defining `Status`, an `enum.Enum` subclass with the members `PENDING`, `RUNNING`, `DONE` and `FAILED`, whose values are the four existing strings.
- Jobs carry `Status` members from now on: a freshly submitted job's status is `Status.PENDING`, and so on through its life cycle.
- The queue, policy and report modules import `Status` and use its members. None of them spells a raw status string any more.
- `Status` is the only definition of the statuses in the package.

**Unchanged behaviour:** callers that compare a job's status with a plain string (`job["status"] == "pending"`), call `with_status("running")`, read `counts()` (keyed by the plain strings) or serialise jobs and counts to JSON see exactly what they see today. The summary line is unchanged. The existing suite must stay green without edits. Run it with `python3 -m pytest -q tests`.
