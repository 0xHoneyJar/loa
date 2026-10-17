"""Every error the command line reports is a UsageError, printed as `tally: <message>`."""


class UsageError(Exception):
    pass
