"""Running a scheduler to completion."""


def drain(scheduler, fn=None):
    """Run every job that can run; return the names in run order.

    ``fn(name)`` is called for each job while it runs.  Jobs that never become
    ready (paused, or waiting for a paused job) are left pending.
    """
    order = []
    while True:
        batch = scheduler.ready()
        if not batch:
            return order
        for name in batch:
            scheduler.start(name)
            if fn is not None:
                fn(name)
            scheduler.complete(name)
            order.append(name)
