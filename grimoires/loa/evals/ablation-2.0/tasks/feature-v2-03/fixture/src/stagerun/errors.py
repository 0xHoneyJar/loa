"""Error types."""


class PipelineError(Exception):
    """Base class of every stagerun error."""


class SpecError(PipelineError):
    """A spec file that does not describe a pipeline."""
