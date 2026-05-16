"""cycle-109 Sprint 2 T2.4 — verdict_quality sidecar transport.

The verdict_quality envelope is constructed in cheval.cmd_invoke's
``finally`` block AFTER the stdout JSON has already been printed.
flatline-orchestrator.sh (CONSUMER #2 per SDD §3.2.3 IMP-004) needs the
envelope back from each per-voice cheval invocation to feed the
multi-voice aggregator. Reading from the shared MODELINV log
(.run/model-invoke.jsonl) is racy under FL's parallel-dispatch shape
(3 voices in flight); the sidecar pattern gives each call its own
write target.

Contract:
  - ``LOA_VERDICT_QUALITY_SIDECAR`` env var unset / empty → no-op.
  - Env var set → write the envelope JSON to that path (compact, no
    whitespace, no trailing newline).
  - ``envelope is None`` → no-op (leave path absent so consumers can
    distinguish "envelope build error" from "successful empty content").
  - Write failure → log ``[verdict-quality-sidecar-failed]`` to stderr
    and return; MUST NOT raise (caller is in cmd_invoke's finally block;
    exception would clobber the actual exit code).

The sidecar file is one-shot per cheval invocation. FL is responsible
for allocating a fresh path per call and reading it back after cheval
returns.
"""

from __future__ import annotations

import json
import os
import sys
from typing import Any, Dict, Optional


_ENV_VAR = "LOA_VERDICT_QUALITY_SIDECAR"


def write_sidecar(envelope: Optional[Dict[str, Any]]) -> None:
    """Write the envelope to the sidecar path if env var is set.

    Args:
      envelope: validated verdict_quality envelope, or None when the
        producer's build path failed and no envelope is available.

    Side effects:
      - Creates / overwrites the file at $LOA_VERDICT_QUALITY_SIDECAR.
      - Stderr-logs on failure with marker ``[verdict-quality-sidecar-failed]``.

    Never raises.
    """
    path = os.environ.get(_ENV_VAR, "").strip()
    if not path:
        return
    if envelope is None:
        # Producer-side build error — leave sidecar absent so consumers
        # can distinguish from "empty content" successful runs.
        return
    try:
        # Compact JSON: matches the bash-twin parsing contract (single
        # line, no whitespace between separators). Open in 'w' mode so
        # any stale content is truncated atomically by the OS.
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(envelope, fh, separators=(",", ":"), ensure_ascii=False)
    except OSError as e:
        # Most common failure: path's parent directory doesn't exist
        # (e.g., consumer-side bug where FL didn't mktemp -p). Log and
        # continue — the MODELINV envelope still carries the field via
        # cheval's existing emit path, so the audit trail is not blinded
        # by sidecar failure.
        print(
            f"[verdict-quality-sidecar-failed] {type(e).__name__}: {e} "
            f"(path={path!r})",
            file=sys.stderr,
        )
    except Exception as e:  # noqa: BLE001 — fail-soft per finally-block contract
        print(
            f"[verdict-quality-sidecar-failed] {type(e).__name__}: {e}",
            file=sys.stderr,
        )
