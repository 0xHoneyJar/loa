/**
 * Manifest Signer — Ed25519 signing and verification using Node.js built-in crypto.
 *
 * No external dependencies required (Ed25519 supported since Node.js 15).
 */

import {
  createHash,
  createPublicKey,
  createPrivateKey,
  sign,
  verify,
  generateKeyPairSync,
  type KeyObject,
} from "crypto";

export interface SignedManifest {
  version: number;
  createdAt: string;
  files: Array<{ path: string; checksum: string; size: number }>;
  signature: string;
}

export class ManifestSigner {
  constructor(
    private readonly privateKey: KeyObject | null,
    private readonly publicKey: KeyObject,
  ) {}

  /**
   * Sign a manifest payload.
   */
  sign(payload: Omit<SignedManifest, "signature">): string {
    if (!this.privateKey) {
      throw new Error("Private key required for signing.");
    }

    const data = Buffer.from(JSON.stringify(payload, Object.keys(payload).sort()));
    const sig = sign(null, data, this.privateKey);
    return sig.toString("base64");
  }

  /**
   * Verify a signed manifest.
   */
  verify(manifest: SignedManifest): boolean {
    const { signature, ...payload } = manifest;
    const data = Buffer.from(JSON.stringify(payload, Object.keys(payload).sort()));

    try {
      return verify(null, data, this.publicKey, Buffer.from(signature, "base64"));
    } catch {
      return false;
    }
  }
}

/**
 * Generate an Ed25519 key pair for dev/test environments.
 * Returns PEM-encoded key strings.
 */
export function generateKeyPair(): { publicKey: string; privateKey: string } {
  const pair = generateKeyPairSync("ed25519", {
    publicKeyEncoding: { type: "spki", format: "pem" },
    privateKeyEncoding: { type: "pkcs8", format: "pem" },
  });

  return {
    publicKey: pair.publicKey as string,
    privateKey: pair.privateKey as string,
  };
}

/**
 * Create a ManifestSigner from PEM-encoded key strings.
 */
export function createManifestSigner(publicKeyPem: string, privateKeyPem?: string): ManifestSigner {
  const publicKey = createPublicKey(publicKeyPem);
  const privateKey = privateKeyPem ? createPrivateKey(privateKeyPem) : null;

  return new ManifestSigner(privateKey, publicKey);
}
