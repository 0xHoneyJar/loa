"""Rendering schedules back into text."""
from . import settings
from .cache import get


def _numbers(nums):
    out = []
    i = 0
    while i < len(nums):
        j = i
        if i + 1 < len(nums):
            step = nums[i + 1] - nums[i]
            j = i + 1
            while j + 1 < len(nums) and nums[j + 1] - nums[j] == step:
                j += 1
        if j - i + 1 >= 3:
            if step == 1:
                out.append("%d-%d" % (nums[i], nums[j]))
            else:
                out.append("%d-%d/%d" % (nums[i], nums[j], step))
            i = j + 1
        else:
            out.append(str(nums[i]))
            i += 1
    return out


def render_field(field):
    lo, hi = settings.BOUNDS[field.name]
    full = set(range(lo, hi + 1))
    if field.name == "day-of-week":
        full = set(v % 7 for v in full)
    if set(field.values) == full:
        parts = ["*"]
    else:
        parts = _numbers(sorted(field.values))
    for kind, n, k in field.specials:
        if kind == "L" or kind == "LW":
            parts.append(kind)
        elif kind == "L-":
            parts.append("L-%d" % n)
        elif kind == "W":
            parts.append("%dW" % n)
        elif kind == "dL":
            parts.append("%dL" % n)
        else:
            parts.append("%d#%d" % (n, k))
    return ",".join(parts)


def normalize(expression):
    """Return the canonical form of an expression string."""
    s = get(expression)
    return " ".join(render_field(f) for f in s.fields())
