"""Fernet-encrypted credential store at ~/.loa/credentials/ (SDD §4.1.4).

Encrypts credentials with AES-128-CBC + HMAC via the cryptography package.
Auto-generates a Fernet key on first use.

Requires: pip install cryptography
"""

from __future__ import annotations

import json
import logging
import os
import stat
from pathlib import Path
from typing import Dict, List, Optional

logger = logging.getLogger(__name__)

from loa_cheval.credentials.providers import CredentialProvider

# Default store location
_DEFAULT_DIR = Path.home() / ".loa" / "credentials"


class EncryptedStore:
    """Read/write encrypted credential storage.

    Storage layout:
        ~/.loa/credentials/
            .key            (Fernet key, 0600)
            store.json.enc  (encrypted JSON dict, 0600)
    """

    def __init__(self, store_dir: Optional[Path] = None):
        self._dir = store_dir or _DEFAULT_DIR
        self._key_path = self._dir / ".key"
        self._store_path = self._dir / "store.json.enc"
        self._fernet = None
        self._cache: Optional[Dict[str, str]] = None

    def _ensure_dir(self) -> None:
        """Create store directory with 0700 permissions."""
        self._dir.mkdir(parents=True, exist_ok=True)
        os.chmod(str(self._dir), stat.S_IRWXU)  # 0700

    def _get_fernet(self):
        """Get or create the Fernet instance."""
        if self._fernet is not None:
            return self._fernet

        try:
            from cryptography.fernet import Fernet
        except ImportError:
            raise RuntimeError(
                "The 'cryptography' package is required for encrypted credential storage.\n"
                "Install it with: pip install cryptography"
            )

        self._ensure_dir()

        if self._key_path.is_file():
            key = self._key_path.read_bytes().strip()
        else:
            key = Fernet.generate_key()
            self._key_path.write_bytes(key + b"\n")
            os.chmod(str(self._key_path), stat.S_IRUSR | stat.S_IWUSR)  # 0600

        self._fernet = Fernet(key)
        return self._fernet

    def _load(self) -> Dict[str, str]:
        """Load and decrypt the store. Returns empty dict if missing/corrupt."""
        if self._cache is not None:
            return self._cache

        if not self._store_path.is_file():
            self._cache = {}
            return self._cache

        fernet = self._get_fernet()
        try:
            encrypted = self._store_path.read_bytes()
            decrypted = fernet.decrypt(encrypted)
            self._cache = json.loads(decrypted)
        except Exception as e:
            # Log the failure so users can diagnose credential loss
            logger.warning(
                "Encrypted credential store at %s could not be decrypted (%s: %s). "
                "Treating as empty. Run '/loa-credentials status' for recovery guidance.",
                self._store_path, type(e).__name__, e,
            )
            self._cache = {}

        return self._cache

    def _save(self, data: Dict[str, str]) -> None:
        """Encrypt and save the store."""
        fernet = self._get_fernet()
        plaintext = json.dumps(data, indent=2).encode()
        encrypted = fernet.encrypt(plaintext)

        self._ensure_dir()
        self._store_path.write_bytes(encrypted)
        os.chmod(str(self._store_path), stat.S_IRUSR | stat.S_IWUSR)  # 0600

        self._cache = data

    def get(self, credential_id: str) -> Optional[str]:
        """Get a credential by ID."""
        return self._load().get(credential_id)

    def set(self, credential_id: str, value: str) -> None:
        """Store a credential."""
        data = dict(self._load())
        data[credential_id] = value
        self._save(data)

    def delete(self, credential_id: str) -> bool:
        """Delete a credential. Returns True if it existed."""
        data = dict(self._load())
        if credential_id in data:
            del data[credential_id]
            self._save(data)
            return True
        return False

    def list_keys(self) -> List[str]:
        """List all stored credential IDs."""
        return list(self._load().keys())


class EncryptedFileProvider(CredentialProvider):
    """Credential provider backed by EncryptedStore."""

    def __init__(self, store_dir: Optional[Path] = None):
        self._store = EncryptedStore(store_dir)

    def get(self, credential_id: str) -> Optional[str]:
        try:
            return self._store.get(credential_id)
        except RuntimeError:
            # cryptography not installed
            return None

    def name(self) -> str:
        return "encrypted (~/.loa/credentials/)"
