import { createHash } from "node:crypto";
export class NodeHasher {
    async sha256(input) {
        return createHash("sha256").update(input).digest("hex");
    }
}
//# sourceMappingURL=node-hasher.js.map