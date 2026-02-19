#!/usr/bin/env python3
"""
Generate test license fixtures with proper RS256 JWT signatures.
Run this script to regenerate test fixtures when needed.
"""

import json
import base64
import hashlib
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path

# For RS256 signing, we'll use cryptography library if available,
# otherwise fall back to OpenSSL subprocess
try:
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import padding
    from cryptography.hazmat.backends import default_backend
    HAS_CRYPTO = True
except ImportError:
    import subprocess
    HAS_CRYPTO = False

FIXTURES_DIR = Path(__file__).parent

# Import ephemeral key generation from mock_server (cycle-028 FR-1)
# Use relative import when run as module, fallback to sys.path manipulation for script mode
try:
    from tests.fixtures.mock_server import generate_test_keypair
except ImportError:
    sys.path.insert(0, str(FIXTURES_DIR))
    from mock_server import generate_test_keypair


def base64url_encode(data: bytes) -> str:
    """Encode bytes to base64url (no padding)."""
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode('ascii')


def base64url_decode(data: str) -> bytes:
    """Decode base64url string to bytes."""
    padding = 4 - len(data) % 4
    if padding != 4:
        data += '=' * padding
    return base64.urlsafe_b64decode(data)


def sign_rs256_crypto(message: bytes, private_key_pem: bytes) -> bytes:
    """Sign message with RS256 using cryptography library."""
    private_key = serialization.load_pem_private_key(
        private_key_pem, password=None, backend=default_backend()
    )
    signature = private_key.sign(
        message,
        padding.PKCS1v15(),
        hashes.SHA256()
    )
    return signature


def sign_rs256_openssl(message: bytes, private_key_path: str) -> bytes:
    """Sign message with RS256 using OpenSSL subprocess."""
    import tempfile
    with tempfile.NamedTemporaryFile(mode='wb', delete=False) as f:
        f.write(message)
        msg_path = f.name

    try:
        result = subprocess.run(
            ['openssl', 'dgst', '-sha256', '-sign', private_key_path, msg_path],
            capture_output=True, check=True
        )
        return result.stdout
    finally:
        os.unlink(msg_path)


def create_jwt(payload: dict, private_key_pem: bytes, private_key_path: str) -> str:
    """Create a signed JWT token."""
    header = {
        "alg": "RS256",
        "typ": "JWT",
        "kid": "test-key-01"
    }

    header_b64 = base64url_encode(json.dumps(header, separators=(',', ':')).encode())
    payload_b64 = base64url_encode(json.dumps(payload, separators=(',', ':')).encode())

    message = f"{header_b64}.{payload_b64}".encode()

    if HAS_CRYPTO:
        signature = sign_rs256_crypto(message, private_key_pem)
    else:
        # Write PEM to temp file for openssl subprocess (cycle-028 FR-1)
        if private_key_path is None:
            import tempfile as _tmpmod
            with _tmpmod.NamedTemporaryFile(mode='wb', suffix='.pem', delete=False) as kf:
                kf.write(private_key_pem)
                private_key_path = kf.name
            try:
                signature = sign_rs256_openssl(message, private_key_path)
            finally:
                os.unlink(private_key_path)
        else:
            signature = sign_rs256_openssl(message, private_key_path)

    signature_b64 = base64url_encode(signature)

    return f"{header_b64}.{payload_b64}.{signature_b64}"


def create_license_file(
    slug: str,
    version: str,
    tier: str,
    expires_at: datetime,
    offline_valid_until: datetime,
    private_key_pem: bytes,
    private_key_path: str
) -> dict:
    """Create a complete license file with signed JWT."""

    # JWT payload
    payload = {
        "sub": "usr_test123",
        "skill": slug,
        "version": version,
        "tier": tier,
        "watermark": "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6",
        "lid": "lic_test789",
        "iss": "https://api.constructs.network",
        "aud": "loa-skills-client",
        "iat": int(datetime.now().timestamp()),
        "exp": int(expires_at.timestamp())
    }

    token = create_jwt(payload, private_key_pem, private_key_path)

    return {
        "schema_version": 1,
        "type": "skill",
        "slug": slug,
        "version": version,
        "registry": "default",
        "token": token,
        "tier": tier,
        "watermark": "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6",
        "issued_at": datetime.now().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "expires_at": expires_at.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "offline_valid_until": offline_valid_until.strftime("%Y-%m-%dT%H:%M:%SZ")
    }


def main():
    # Use ephemeral generated key (cycle-028 FR-1 — no more static PEM files)
    private_key_pem, _ = generate_test_keypair()
    private_key_path = None  # Not used when HAS_CRYPTO=True

    now = datetime.utcnow()

    # 1. Valid license (expires in 30 days)
    valid_license = create_license_file(
        slug="test-vendor/valid-skill",
        version="1.0.0",
        tier="pro",
        expires_at=now + timedelta(days=30),
        offline_valid_until=now + timedelta(days=31),
        private_key_pem=private_key_pem,
        private_key_path=private_key_path
    )
    with open(FIXTURES_DIR / "valid_license.json", 'w') as f:
        json.dump(valid_license, f, indent=2)
    print("Created: valid_license.json")

    # 2. Expired license (expired 10 days ago, grace period also expired)
    expired_license = create_license_file(
        slug="test-vendor/expired-skill",
        version="1.0.0",
        tier="pro",
        expires_at=now - timedelta(days=10),
        offline_valid_until=now - timedelta(days=9),
        private_key_pem=private_key_pem,
        private_key_path=private_key_path
    )
    with open(FIXTURES_DIR / "expired_license.json", 'w') as f:
        json.dump(expired_license, f, indent=2)
    print("Created: expired_license.json")

    # 3. Grace period license (expired 12 hours ago, grace still valid)
    grace_license = create_license_file(
        slug="test-vendor/grace-skill",
        version="1.0.0",
        tier="pro",
        expires_at=now - timedelta(hours=12),
        offline_valid_until=now + timedelta(hours=12),
        private_key_pem=private_key_pem,
        private_key_path=private_key_path
    )
    with open(FIXTURES_DIR / "grace_period_license.json", 'w') as f:
        json.dump(grace_license, f, indent=2)
    print("Created: grace_period_license.json")

    # 4. Invalid signature license (valid license with tampered token)
    invalid_sig_license = valid_license.copy()
    invalid_sig_license["slug"] = "test-vendor/invalid-sig-skill"
    # Tamper with the token by changing some characters
    invalid_sig_license["token"] = invalid_sig_license["token"][:-10] + "TAMPERED!!"
    with open(FIXTURES_DIR / "invalid_signature_license.json", 'w') as f:
        json.dump(invalid_sig_license, f, indent=2)
    print("Created: invalid_signature_license.json")

    # 5. Team tier license (72 hour grace period)
    team_license = create_license_file(
        slug="test-vendor/team-skill",
        version="2.0.0",
        tier="team",
        expires_at=now + timedelta(days=60),
        offline_valid_until=now + timedelta(days=63),  # 72 hours grace
        private_key_pem=private_key_pem,
        private_key_path=private_key_path
    )
    with open(FIXTURES_DIR / "team_license.json", 'w') as f:
        json.dump(team_license, f, indent=2)
    print("Created: team_license.json")

    # 6. Enterprise tier license (168 hour grace period)
    enterprise_license = create_license_file(
        slug="test-vendor/enterprise-skill",
        version="3.0.0",
        tier="enterprise",
        expires_at=now + timedelta(days=90),
        offline_valid_until=now + timedelta(days=97),  # 168 hours grace
        private_key_pem=private_key_pem,
        private_key_path=private_key_path
    )
    with open(FIXTURES_DIR / "enterprise_license.json", 'w') as f:
        json.dump(enterprise_license, f, indent=2)
    print("Created: enterprise_license.json")

    print("\nAll test fixtures generated successfully!")


if __name__ == "__main__":
    main()
