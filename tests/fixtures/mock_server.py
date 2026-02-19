#!/usr/bin/env python3
"""
Mock Server for Loa Constructs Testing.

This server simulates the Loa Constructs API for local testing.
It serves test fixtures and responds to all registry endpoints.

Usage:
    python3 tests/fixtures/mock_server.py [--port PORT]

    Default port: 8765

Endpoints:
    GET  /v1/health                       - Health check
    GET  /v1/public-keys/:key_id          - Get signing public key
    GET  /v1/skills/:vendor/:name         - Get skill metadata
    GET  /v1/skills/:vendor/:name/content - Download skill content
    POST /v1/licenses/validate            - Validate license token
    GET  /v1/packs/:vendor/:name          - Get pack metadata
    GET  /v1/packs/:vendor/:name/content  - Download pack content
"""

import argparse
import base64
import hashlib
import json
import os
import sys
import tarfile
import tempfile
from datetime import datetime, timedelta
from http.server import HTTPServer, BaseHTTPRequestHandler
from io import BytesIO
from pathlib import Path
from urllib.parse import urlparse, parse_qs

try:
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.hazmat.primitives import serialization
    _HAS_CRYPTO = True
except ImportError:
    import subprocess as _subprocess
    _HAS_CRYPTO = False

# Directory containing test fixtures
FIXTURES_DIR = Path(__file__).parent


def generate_test_keypair():
    """Generate ephemeral RSA keypair for test use only.

    Returns (private_pem_bytes, public_pem_bytes) tuple.
    Keys are 2048-bit RSA, generated fresh each time the module loads.
    Uses cryptography library if available, falls back to openssl subprocess.
    """
    if _HAS_CRYPTO:
        private_key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048,
        )
        private_pem = private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        )
        public_pem = private_key.public_key().public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        )
        return private_pem, public_pem
    else:
        # Fallback: use openssl command-line tool
        result = _subprocess.run(
            ['openssl', 'genpkey', '-algorithm', 'RSA', '-pkeyopt', 'rsa_keygen_bits:2048'],
            capture_output=True, check=True
        )
        private_pem = result.stdout
        result = _subprocess.run(
            ['openssl', 'pkey', '-pubout'],
            input=private_pem, capture_output=True, check=True
        )
        public_pem = result.stdout
        return private_pem, public_pem


# Generate ephemeral test keys at module load time (cycle-028 FR-1)
_PRIVATE_PEM, _PUBLIC_PEM = generate_test_keypair()


def load_public_key():
    """Return the ephemeral mock public key as a string."""
    return _PUBLIC_PEM.decode('utf-8')


# Mock skill data
MOCK_SKILLS = {
    "test-vendor/valid-skill": {
        "slug": "test-vendor/valid-skill",
        "name": "Valid Skill",
        "description": "A test skill for validation",
        "version": "1.0.0",
        "latest_version": "1.1.0",  # Update available
        "author": "Test Vendor",
        "license_required": True,
        "tiers": ["free", "pro", "team", "enterprise"],
        "created_at": "2025-01-01T00:00:00Z",
        "updated_at": "2025-01-15T00:00:00Z"
    },
    "test-vendor/expired-skill": {
        "slug": "test-vendor/expired-skill",
        "name": "Expired Skill",
        "description": "A skill with expired license",
        "version": "1.0.0",
        "latest_version": "1.0.0",  # No update
        "author": "Test Vendor",
        "license_required": True,
        "tiers": ["pro"],
        "created_at": "2025-01-01T00:00:00Z",
        "updated_at": "2025-01-15T00:00:00Z"
    },
    "test-vendor/free-skill": {
        "slug": "test-vendor/free-skill",
        "name": "Free Skill",
        "description": "A free skill (no license required)",
        "version": "1.0.0",
        "latest_version": "2.0.0",  # Major update available
        "author": "Test Vendor",
        "license_required": False,
        "tiers": ["free"],
        "created_at": "2025-01-01T00:00:00Z",
        "updated_at": "2025-01-15T00:00:00Z"
    },
    "test-vendor/up-to-date-skill": {
        "slug": "test-vendor/up-to-date-skill",
        "name": "Up To Date Skill",
        "description": "A skill already at latest version",
        "version": "1.0.0",
        "latest_version": "1.0.0",  # No update
        "author": "Test Vendor",
        "license_required": True,
        "tiers": ["free", "pro"],
        "created_at": "2025-01-01T00:00:00Z",
        "updated_at": "2025-01-15T00:00:00Z"
    }
}

# Mock pack data
MOCK_PACKS = {
    "test-vendor/starter-pack": {
        "slug": "test-vendor/starter-pack",
        "name": "Starter Pack",
        "description": "A bundle of starter skills",
        "version": "1.0.0",
        "author": "Test Vendor",
        "skills": [
            {"slug": "test-vendor/valid-skill", "version": "1.0.0"},
            {"slug": "test-vendor/free-skill", "version": "1.0.0"}
        ],
        "created_at": "2025-01-01T00:00:00Z",
        "updated_at": "2025-01-15T00:00:00Z"
    }
}


def create_skill_tarball(skill_slug: str) -> bytes:
    """Create a mock skill tarball."""
    buffer = BytesIO()
    with tarfile.open(fileobj=buffer, mode='w:gz') as tar:
        # Create SKILL.md
        skill_md = f"""# {skill_slug}

This is a mock skill for testing purposes.

## Instructions

Follow the test instructions here.
"""
        skill_md_bytes = skill_md.encode('utf-8')
        info = tarfile.TarInfo(name="SKILL.md")
        info.size = len(skill_md_bytes)
        tar.addfile(info, BytesIO(skill_md_bytes))

        # Create index.yaml
        index_yaml = f"""name: {skill_slug.split('/')[-1]}
version: "1.0.0"
description: Mock skill for testing
"""
        index_yaml_bytes = index_yaml.encode('utf-8')
        info = tarfile.TarInfo(name="index.yaml")
        info.size = len(index_yaml_bytes)
        tar.addfile(info, BytesIO(index_yaml_bytes))

    return buffer.getvalue()


def create_pack_tarball(pack_slug: str, skills: list) -> bytes:
    """Create a mock pack tarball with nested skills."""
    buffer = BytesIO()
    with tarfile.open(fileobj=buffer, mode='w:gz') as tar:
        # Create pack.yaml manifest
        pack_yaml = f"""name: {pack_slug.split('/')[-1]}
version: "1.0.0"
skills:
"""
        for skill in skills:
            pack_yaml += f"  - slug: {skill['slug']}\n"
            pack_yaml += f"    version: {skill['version']}\n"

        pack_yaml_bytes = pack_yaml.encode('utf-8')
        info = tarfile.TarInfo(name="pack.yaml")
        info.size = len(pack_yaml_bytes)
        tar.addfile(info, BytesIO(pack_yaml_bytes))

        # Create skill directories
        for skill in skills:
            skill_dir = skill['slug'].replace('/', '-')
            skill_md = f"# {skill['slug']}\n\nMock skill content."
            skill_md_bytes = skill_md.encode('utf-8')
            info = tarfile.TarInfo(name=f"{skill_dir}/SKILL.md")
            info.size = len(skill_md_bytes)
            tar.addfile(info, BytesIO(skill_md_bytes))

    return buffer.getvalue()


class MockRegistryHandler(BaseHTTPRequestHandler):
    """HTTP request handler for mock registry."""

    def log_message(self, format, *args):
        """Log requests to stderr."""
        sys.stderr.write(f"[{datetime.now().isoformat()}] {args[0]}\n")

    def send_json(self, data: dict, status: int = 200):
        """Send JSON response."""
        body = json.dumps(data, indent=2).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', len(body))
        self.end_headers()
        self.wfile.write(body)

    def send_error_json(self, status: int, message: str, code: str = "ERROR"):
        """Send JSON error response."""
        self.send_json({
            "error": {
                "code": code,
                "message": message
            }
        }, status)

    def send_binary(self, data: bytes, content_type: str = 'application/octet-stream'):
        """Send binary response."""
        self.send_response(200)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', len(data))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        """Handle GET requests."""
        parsed = urlparse(self.path)
        path = parsed.path

        # Health check
        if path == '/v1/health':
            self.send_json({
                "status": "healthy",
                "version": "1.0.0-mock",
                "timestamp": datetime.utcnow().isoformat() + "Z"
            })
            return

        # Public keys
        if path.startswith('/v1/public-keys/'):
            key_id = path.split('/')[-1]
            if key_id in ['test-key-01', 'default']:
                self.send_json({
                    "key_id": key_id,
                    "algorithm": "RS256",
                    "public_key": load_public_key(),
                    "created_at": "2025-01-01T00:00:00Z",
                    "expires_at": "2030-01-01T00:00:00Z"
                })
            else:
                self.send_error_json(404, f"Public key '{key_id}' not found", "KEY_NOT_FOUND")
            return

        # Skills versions endpoint
        if path.startswith('/v1/skills/') and path.endswith('/versions'):
            parts = path.split('/')
            if len(parts) >= 6:
                vendor = parts[3]
                name = parts[4]
                slug = f"{vendor}/{name}"

                if slug in MOCK_SKILLS:
                    skill = MOCK_SKILLS[slug]
                    self.send_json({
                        "slug": slug,
                        "current_version": skill.get('version', '1.0.0'),
                        "latest_version": skill.get('latest_version', skill.get('version', '1.0.0')),
                        "versions": [
                            {"version": skill.get('latest_version', '1.0.0'), "released_at": "2026-01-01T00:00:00Z"},
                            {"version": skill.get('version', '1.0.0'), "released_at": "2025-01-01T00:00:00Z"}
                        ],
                        "update_available": skill.get('latest_version', skill.get('version')) != skill.get('version')
                    })
                else:
                    self.send_error_json(404, f"Skill '{slug}' not found", "SKILL_NOT_FOUND")
            else:
                self.send_error_json(400, "Invalid skill path", "INVALID_PATH")
            return

        # Skills metadata
        if path.startswith('/v1/skills/') and not path.endswith('/content') and not path.endswith('/versions'):
            parts = path.split('/')
            if len(parts) >= 5:
                vendor = parts[3]
                name = parts[4]
                slug = f"{vendor}/{name}"

                if slug in MOCK_SKILLS:
                    self.send_json(MOCK_SKILLS[slug])
                else:
                    self.send_error_json(404, f"Skill '{slug}' not found", "SKILL_NOT_FOUND")
            else:
                self.send_error_json(400, "Invalid skill path", "INVALID_PATH")
            return

        # Skills content (tarball download)
        if path.startswith('/v1/skills/') and path.endswith('/content'):
            parts = path.split('/')
            if len(parts) >= 6:
                vendor = parts[3]
                name = parts[4]
                slug = f"{vendor}/{name}"

                if slug in MOCK_SKILLS:
                    tarball = create_skill_tarball(slug)
                    self.send_binary(tarball, 'application/gzip')
                else:
                    self.send_error_json(404, f"Skill '{slug}' not found", "SKILL_NOT_FOUND")
            else:
                self.send_error_json(400, "Invalid skill path", "INVALID_PATH")
            return

        # Packs metadata
        if path.startswith('/v1/packs/') and not path.endswith('/content'):
            parts = path.split('/')
            if len(parts) >= 5:
                vendor = parts[3]
                name = parts[4]
                slug = f"{vendor}/{name}"

                if slug in MOCK_PACKS:
                    self.send_json(MOCK_PACKS[slug])
                else:
                    self.send_error_json(404, f"Pack '{slug}' not found", "PACK_NOT_FOUND")
            else:
                self.send_error_json(400, "Invalid pack path", "INVALID_PATH")
            return

        # Packs content (tarball download)
        if path.startswith('/v1/packs/') and path.endswith('/content'):
            parts = path.split('/')
            if len(parts) >= 6:
                vendor = parts[3]
                name = parts[4]
                slug = f"{vendor}/{name}"

                if slug in MOCK_PACKS:
                    pack = MOCK_PACKS[slug]
                    tarball = create_pack_tarball(slug, pack['skills'])
                    self.send_binary(tarball, 'application/gzip')
                else:
                    self.send_error_json(404, f"Pack '{slug}' not found", "PACK_NOT_FOUND")
            else:
                self.send_error_json(400, "Invalid pack path", "INVALID_PATH")
            return

        # Unknown endpoint
        self.send_error_json(404, f"Endpoint '{path}' not found", "NOT_FOUND")

    def do_POST(self):
        """Handle POST requests."""
        parsed = urlparse(self.path)
        path = parsed.path

        # License validation
        if path == '/v1/licenses/validate':
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length)

            try:
                data = json.loads(body)
                token = data.get('token', '')

                # Simple validation - check if token is well-formed JWT
                parts = token.split('.')
                if len(parts) != 3:
                    self.send_json({
                        "valid": False,
                        "error": "INVALID_TOKEN_FORMAT",
                        "message": "Token must be a valid JWT"
                    })
                    return

                # Check for tampered token
                if 'TAMPERED' in token:
                    self.send_json({
                        "valid": False,
                        "error": "INVALID_SIGNATURE",
                        "message": "Token signature verification failed"
                    })
                    return

                # Decode payload (base64url)
                try:
                    payload_b64 = parts[1]
                    # Add padding if needed
                    padding = 4 - len(payload_b64) % 4
                    if padding != 4:
                        payload_b64 += '=' * padding
                    payload_json = base64.urlsafe_b64decode(payload_b64)
                    payload = json.loads(payload_json)

                    # Check expiration
                    exp = payload.get('exp', 0)
                    now = datetime.utcnow().timestamp()

                    if exp < now:
                        # Calculate how long ago it expired
                        expired_ago = now - exp
                        hours_ago = expired_ago / 3600

                        self.send_json({
                            "valid": False,
                            "error": "TOKEN_EXPIRED",
                            "message": f"Token expired {hours_ago:.1f} hours ago",
                            "expired_at": datetime.utcfromtimestamp(exp).isoformat() + "Z"
                        })
                        return

                    # Token is valid
                    self.send_json({
                        "valid": True,
                        "skill": payload.get('skill'),
                        "tier": payload.get('tier'),
                        "expires_at": datetime.utcfromtimestamp(exp).isoformat() + "Z",
                        "license_id": payload.get('lid')
                    })

                except Exception as e:
                    self.send_json({
                        "valid": False,
                        "error": "DECODE_ERROR",
                        "message": str(e)
                    })

            except json.JSONDecodeError:
                self.send_error_json(400, "Invalid JSON body", "INVALID_JSON")
            return

        # Unknown endpoint
        self.send_error_json(404, f"Endpoint '{path}' not found", "NOT_FOUND")


def main():
    parser = argparse.ArgumentParser(description='Mock Loa Constructs Server')
    parser.add_argument('--port', type=int, default=8765, help='Port to listen on')
    parser.add_argument('--host', default='127.0.0.1', help='Host to bind to')
    args = parser.parse_args()

    server = HTTPServer((args.host, args.port), MockRegistryHandler)
    print(f"Mock Loa Constructs Server starting on http://{args.host}:{args.port}")
    print(f"Fixtures directory: {FIXTURES_DIR}")
    print("Press Ctrl+C to stop")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()


if __name__ == '__main__':
    main()
