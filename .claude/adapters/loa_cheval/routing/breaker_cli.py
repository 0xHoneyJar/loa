"""Operator CLI for provider circuit breakers (cycle-125 FR-4, SDD §1.5).

    python3 -m loa_cheval.routing.breaker_cli --list [--json] [--run-dir DIR] [--reset-timeout N]
    python3 -m loa_cheval.routing.breaker_cli --reset PROVIDER[:AUTH_TYPE] [--reason TEXT] [--json]

Thin wrapper over ``circuit_breaker._cli`` (``bucket_snapshot`` / ``reset_bucket``).
It lives in its own module because ``loa_cheval.routing`` imports
``circuit_breaker`` eagerly, so ``python -m loa_cheval.routing.circuit_breaker``
works but prints runpy's "found in sys.modules" RuntimeWarning first; this
entry point is warning-free and is what ``loa-status.sh`` and ``cheval
--reset-breaker`` use.
"""
from __future__ import annotations

import sys

from loa_cheval.routing.circuit_breaker import _cli

if __name__ == "__main__":
    sys.exit(_cli(sys.argv[1:]))
