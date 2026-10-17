"""Resolving a set of requirements against the versions on offer."""
from .index import VersionIndex


def resolve(requirements, available):
    """Map every required name to the highest version in its range.

    ``requirements`` maps a name to a range string; ``available`` maps a
    name to a list of version strings.  A name without a matching version
    maps to None.  One index is built per name.
    """
    indexes = {name: VersionIndex(available.get(name, ()))
               for name in requirements}
    return {name: indexes[name].max_satisfying(spec)
            for name, spec in requirements.items()}


def format_report(requirements, available):
    """One line per requirement, sorted by name: ``name range -> version``."""
    picked = resolve(requirements, available)
    lines = []
    for name in sorted(requirements):
        choice = picked[name]
        lines.append(f"{name} {requirements[name]} -> "
                     f"{choice if choice is not None else 'unresolved'}")
    return "\n".join(lines) + ("\n" if lines else "")
