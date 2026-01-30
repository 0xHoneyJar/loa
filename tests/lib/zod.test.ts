import { describe, it, expect } from "vitest";
import { questQuerySchema, raffleQuerySchema } from "@/lib/zod/quests";

describe("questQuerySchema", () => {
  it("validates valid quest name", () => {
    const result = questQuerySchema.safeParse({ questName: "Test Quest" });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.questName).toBe("Test Quest");
    }
  });

  it("rejects missing quest name", () => {
    const result = questQuerySchema.safeParse({});
    expect(result.success).toBe(false);
  });

  it("rejects null quest name", () => {
    const result = questQuerySchema.safeParse({ questName: null });
    expect(result.success).toBe(false);
  });

  it("accepts empty string", () => {
    const result = questQuerySchema.safeParse({ questName: "" });
    expect(result.success).toBe(true);
  });
});

describe("raffleQuerySchema", () => {
  it("validates valid raffle name", () => {
    const result = raffleQuerySchema.safeParse({ raffleName: "Weekly Raffle" });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.raffleName).toBe("Weekly Raffle");
    }
  });

  it("rejects missing raffle name", () => {
    const result = raffleQuerySchema.safeParse({});
    expect(result.success).toBe(false);
  });

  it("rejects null raffle name", () => {
    const result = raffleQuerySchema.safeParse({ raffleName: null });
    expect(result.success).toBe(false);
  });
});
