"""Exception hierarchy.  Every error cronq raises on bad input is a CronqError."""


class CronqError(Exception):
    """Base class of every cronq error."""


class TimeFormatError(CronqError):
    """An instant or an offset is not in the accepted text form."""


class ZoneError(CronqError):
    """The zone table file is malformed, or a zone is unknown."""


class ScheduleError(CronqError):
    """A schedule text cannot be parsed, or a schedule cannot be evaluated."""


class JobsError(CronqError):
    """The jobs file is malformed."""


class ConfigError(CronqError):
    """The config file is malformed."""


class UsageError(CronqError):
    """The command line is malformed."""
