"""Error types. Every error the command line reports is a UsageError."""


class UsageError(Exception):
    """A problem with the invocation; reported as `textpipe: <message>`."""


class RegistryError(UsageError):
    """A filter name that cannot be resolved or registered."""


class ConfigError(UsageError):
    """A problem with the config file; the message starts with `config: `."""

    def __init__(self, message):
        super().__init__(f"config: {message}")
