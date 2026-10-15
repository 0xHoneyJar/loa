"""The job queue. A job is a dict: id, name, status, attempts.

Statuses: "pending" (queued), "running", "done", "failed".
"""
import itertools


class BoardError(RuntimeError):
    pass


class Board:
    def __init__(self, max_attempts: int = 3):
        self.jobs = []
        self.max_attempts = max_attempts
        self._ids = itertools.count(1)

    def submit(self, name: str) -> dict:
        job = {"id": next(self._ids), "name": name, "status": "pending", "attempts": 0}
        self.jobs.append(job)
        return job

    def get(self, job_id: int) -> dict:
        for job in self.jobs:
            if job["id"] == job_id:
                return job
        raise BoardError(f"no job {job_id}")

    def start_next(self):
        """Start the oldest pending job; None when nothing is pending."""
        for job in self.jobs:
            if job["status"] == "pending":
                job["status"] = "running"
                job["attempts"] += 1
                return job
        return None

    def finish(self, job_id: int, ok: bool) -> dict:
        job = self.get(job_id)
        if job["status"] != "running":
            raise BoardError(f"job {job_id} is not running")
        if ok:
            job["status"] = "done"
        elif job["attempts"] < self.max_attempts:
            job["status"] = "pending"
        else:
            job["status"] = "failed"
        return job

    def with_status(self, status: str) -> list:
        if status not in ("pending", "running", "done", "failed"):
            raise BoardError(f"unknown status {status!r}")
        return [j for j in self.jobs if j["status"] == status]
