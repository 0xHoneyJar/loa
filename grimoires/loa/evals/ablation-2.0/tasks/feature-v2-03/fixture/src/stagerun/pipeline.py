"""A pipeline: named steps applied in order, each to the previous step's output."""
from .errors import PipelineError
from .spec import parse_spec


class Pipeline:
    def __init__(self, steps):
        steps = list(steps)
        if not steps:
            raise PipelineError("a pipeline needs at least one step")
        for number, step in enumerate(steps, start=1):
            if not (isinstance(step, tuple) and len(step) == 2 and isinstance(step[0], str) and step[0] and callable(step[1])):
                raise PipelineError(f"bad step {number}: expected a (name, function) pair")
        self.steps = steps

    @classmethod
    def from_spec(cls, text):
        return cls(parse_spec(text))

    def names(self):
        return [name for name, _ in self.steps]

    def run(self, data):
        """Feed ``data`` through every step; the last step's output."""
        for _, function in self.steps:
            data = function(data)
        return data
