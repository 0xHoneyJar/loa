"""cheval audit-emit subpackage.

Adapters that translate cheval invocation events into cycle-098-shaped
audit envelopes. Currently houses the MODELINV (model-invocation) primitive
emitter per cycle-102 Sprint 1D.
"""

from loa_cheval.audit.modelinv import (
    RedactionFailure,
    assert_no_secret_shapes_remain,
    emit_model_invoke_complete,
    redact_payload_strings,
)

__all__ = [
    "RedactionFailure",
    "assert_no_secret_shapes_remain",
    "emit_model_invoke_complete",
    "redact_payload_strings",
]
