"""Credential providers — layered chain for secret resolution (SDD §4.1.4).

Precedence (highest → lowest):
  1. EnvProvider       — os.environ
  2. EncryptedFileProvider — ~/.loa/credentials/store.json.enc (Fernet)
  3. DotenvProvider     — .env.local in project root
"""

from __future__ import annotations

import os
import re
from abc import ABC, abstractmethod
from pathlib import Path
from typing import Dict, List, Optional


class CredentialProvider(ABC):
    """Abstract base for credential sources."""

    @abstractmethod
    def get(self, credential_id: str) -> Optional[str]:
        """Return credential value or None if not found."""

    @abstractmethod
    def name(self) -> str:
        """Human-readable provider name for diagnostics."""


class EnvProvider(CredentialProvider):
    """Reads credentials from environment variables."""

    def get(self, credential_id: str) -> Optional[str]:
        return os.environ.get(credential_id)

    def name(self) -> str:
        return "environment"


class DotenvProvider(CredentialProvider):
    """Reads credentials from a .env.local file in the project root.

    Parses KEY=VALUE lines. Ignores comments (#) and blank lines.
    Strips optional quotes from values.
    """

    _DOTENV_LINE = re.compile(
        r"""^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$"""
    )

    def __init__(self, project_root: str):
        self._cache: Optional[Dict[str, str]] = None
        self._cache_mtime: float = 0.0
        self._path = Path(project_root) / ".env.local"

    def _load(self) -> Dict[str, str]:
        if not self._path.is_file():
            self._cache = {}
            self._cache_mtime = 0.0
            return self._cache
        # Invalidate cache if file has been modified
        try:
            current_mtime = self._path.stat().st_mtime
        except OSError:
            self._cache = {}
            return self._cache
        if self._cache is not None and current_mtime == self._cache_mtime:
            return self._cache
        self._cache = {}
        self._cache_mtime = current_mtime
        for line in self._path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            m = self._DOTENV_LINE.match(line)
            if m:
                key = m.group(1)
                val = m.group(2).strip()
                # Strip surrounding quotes
                if len(val) >= 2 and val[0] == val[-1] and val[0] in ('"', "'"):
                    val = val[1:-1]
                self._cache[key] = val
        return self._cache

    def get(self, credential_id: str) -> Optional[str]:
        return self._load().get(credential_id)

    def name(self) -> str:
        return "dotenv (.env.local)"


class CompositeProvider(CredentialProvider):
    """Chains multiple providers in priority order. First non-None wins."""

    def __init__(self, providers: List[CredentialProvider]):
        self._providers = list(providers)

    def get(self, credential_id: str) -> Optional[str]:
        for provider in self._providers:
            val = provider.get(credential_id)
            if val is not None:
                return val
        return None

    def name(self) -> str:
        names = [p.name() for p in self._providers]
        return f"composite({' → '.join(names)})"

    @property
    def providers(self) -> List[CredentialProvider]:
        """Expose chain for diagnostics."""
        return list(self._providers)


def get_credential_provider(project_root: str) -> CompositeProvider:
    """Factory: build the default credential provider chain.

    Chain: env → encrypted store (if available) → .env.local
    """
    chain: List[CredentialProvider] = [EnvProvider()]

    # Try to include encrypted store (optional dependency)
    try:
        from loa_cheval.credentials.store import EncryptedFileProvider
        chain.append(EncryptedFileProvider())
    except Exception:
        pass  # cryptography not installed or store not initialized

    chain.append(DotenvProvider(project_root))
    return CompositeProvider(chain)
