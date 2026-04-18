"""loa_cheval — Hounfour multi-model provider adapter for Loa framework.

Public API surface for upstream consumers (loa-finn, constructs).
"""

from loa_cheval.__version__ import __version__
from loa_cheval.types import (
    AgentBinding,
    BudgetExceededError,
    ChevalError,
    Citation,
    CompletionRequest,
    CompletionResult,
    ConfigError,
    ContextTooLargeError,
    GroundedQuality,
    GroundedResult,
    GroundingProvenance,
    InvalidInputError,
    ModelConfig,
    NativeRuntimeRequired,
    ProviderConfig,
    ProviderUnavailableError,
    RateLimitError,
    ResolvedModel,
    RetriesExhaustedError,
    Usage,
)

# Shared contract version advertised by --capabilities and pinned against
# construct-k-hole's `compatible_contract_versions` per SDD §13.1.
CONTRACT_VERSION = "1.0"

__all__ = [
    "__version__",
    "CONTRACT_VERSION",
    "AgentBinding",
    "BudgetExceededError",
    "ChevalError",
    "Citation",
    "CompletionRequest",
    "CompletionResult",
    "ConfigError",
    "ContextTooLargeError",
    "GroundedQuality",
    "GroundedResult",
    "GroundingProvenance",
    "InvalidInputError",
    "ModelConfig",
    "NativeRuntimeRequired",
    "ProviderConfig",
    "ProviderUnavailableError",
    "RateLimitError",
    "ResolvedModel",
    "RetriesExhaustedError",
    "Usage",
]
