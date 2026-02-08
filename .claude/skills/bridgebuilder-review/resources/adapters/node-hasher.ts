import { createHash } from "node:crypto";
import type { IHasher } from "../ports/hasher.js";

export class NodeHasher implements IHasher {
  async sha256(input: string): Promise<string> {
    return createHash("sha256").update(input).digest("hex");
  }
}
