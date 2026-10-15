"""Status counts and a one-line summary."""


def counts(jobs: list) -> dict:
    out = {"pending": 0, "running": 0, "done": 0, "failed": 0}
    for job in jobs:
        out[job["status"]] += 1
    return out


def summary_line(jobs: list) -> str:
    c = counts(jobs)
    total = sum(c.values())
    if total == 0:
        return "no jobs"
    finished = c["done"] + c["failed"]
    parts = [f"{c[s]} {s}" for s in ("pending", "running", "done", "failed") if c[s]]
    return f"{total} jobs ({', '.join(parts)}); {100 * finished // total}% finished"
