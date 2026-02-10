"""loa_cheval — Hounfour multi-model provider adapter for Loa framework.

Public API surface for upstream consumers (loa-finn, constructs).
"""

from loa_cheval.__version__ import __version__
from loa_cheval.types import (
    AgentBinding,
    BudgetExceededError,
    ChevalError,
    CompletionRequest,
    CompletionResult,
    ConfigError,
    ContextTooLargeError,
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

__all__ = [
    "__version__",
    "AgentBinding",
    "BudgetExceededError",
    "ChevalError",
    "CompletionRequest",
    "CompletionResult",
    "ConfigError",
    "ContextTooLargeError",
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
