"""What may happen to a job next."""


def is_terminal(job: dict) -> bool:
    return job["status"] == "done" or job["status"] == "failed"


def can_cancel(job: dict) -> bool:
    return job["status"] == "pending"


def next_actions(job: dict) -> list:
    if job["status"] == "pending":
        return ["start", "cancel"]
    if job["status"] == "running":
        return ["finish"]
    if job["status"] == "failed":
        return ["resubmit"]
    return []
