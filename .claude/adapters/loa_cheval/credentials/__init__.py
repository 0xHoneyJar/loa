"""Credential provider chain for Loa/Hounfour (SDD §4.1.4).

Provides a layered credential resolution strategy:
  1. Environment variables (highest priority)
  2. Encrypted file store (~/.loa/credentials/)
  3. .env.local project-level dotenv (lowest priority)
"""

from loa_cheval.credentials.providers import (
    CompositeProvider,
    CredentialProvider,
    DotenvProvider,
    EnvProvider,
    get_credential_provider,
)

__all__ = [
    "CompositeProvider",
    "CredentialProvider",
    "DotenvProvider",
    "EnvProvider",
    "get_credential_provider",
]
