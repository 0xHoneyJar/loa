"""Policy engine module for Simstim (ICE).

Provides auto-approve policy matching and evaluation for
permission requests based on configurable patterns.
"""

from simstim.policies.engine import PolicyEngine
from simstim.policies.models import PolicyMatch, PolicyEvaluationResult

__all__ = [
    "PolicyEngine",
    "PolicyMatch",
    "PolicyEvaluationResult",
]
