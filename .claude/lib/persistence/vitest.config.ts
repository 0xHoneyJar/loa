import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    testTimeout: 30_000,
    include: [".claude/lib/persistence/__tests__/**/*.test.ts"],
    exclude: ["**/node_modules/**"],
  },
});
