import type { IHasher } from "../ports/hasher.js";
export declare class NodeHasher implements IHasher {
    sha256(input: string): Promise<string>;
}
//# sourceMappingURL=node-hasher.d.ts.map