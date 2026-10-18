"""Little helpers used all over the place."""
import re

DEBUG = False

_ident_re = re.compile(r"^[0-9A-Za-z-]+$")


def debug(*args):
    if DEBUG:
        print("[semverkit]", *args)


def _strip(text):
    body = text.strip()
    if body.startswith("="):
        body = body[1:]
    if body[:1] in ("v", "V"):
        body = body[1:]
    return body


def _sign(a, b):
    return (a > b) - (a < b)


def _is_num(s):
    return s.isascii() and s.isdigit()


def _fmt(major, minor, patch, pre=(), build=()):
    s = "%d.%d.%d" % (major, minor, patch)
    if pre:
        s += "-" + ".".join(str(x) for x in pre)
    if build:
        s += "+" + ".".join(build)
    return s


def isWord(ident):
    if not ident:
        return False
    for c in ident:
        if not (c.isascii() and (c.isalnum() or c == "-")):
            return False
    return not ident.isdigit()
