class PatchError(ValueError):
    """Base class of every error the package raises."""


class PointerError(PatchError):
    pass


class PathError(PatchError):
    pass


class OperationError(PatchError):
    pass


class TestFailed(PatchError):
    pass


class InputError(PatchError):
    pass
