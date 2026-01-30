import { describe, it, expect } from "vitest";
import {
  cn,
  convertSecondsToMinutes,
  calculateTimeRemaining,
  convertUnixToLocalTime,
  formatToken,
} from "@/lib/utils";

describe("cn", () => {
  it("merges class names", () => {
    expect(cn("foo", "bar")).toBe("foo bar");
  });

  it("handles conditional classes", () => {
    expect(cn("foo", false && "bar", "baz")).toBe("foo baz");
  });

  it("merges tailwind classes correctly", () => {
    expect(cn("px-2", "px-4")).toBe("px-4");
    expect(cn("text-red-500", "text-blue-500")).toBe("text-blue-500");
  });

  it("handles arrays", () => {
    expect(cn(["foo", "bar"])).toBe("foo bar");
  });
});

describe("convertSecondsToMinutes", () => {
  it("converts 0 seconds", () => {
    expect(convertSecondsToMinutes(0)).toBe("0:00");
  });

  it("converts seconds less than a minute", () => {
    expect(convertSecondsToMinutes(30)).toBe("0:30");
    expect(convertSecondsToMinutes(5)).toBe("0:05");
  });

  it("converts full minutes", () => {
    expect(convertSecondsToMinutes(60)).toBe("1:00");
    expect(convertSecondsToMinutes(120)).toBe("2:00");
  });

  it("converts minutes and seconds", () => {
    expect(convertSecondsToMinutes(90)).toBe("1:30");
    expect(convertSecondsToMinutes(185)).toBe("3:05");
  });

  it("handles NaN input", () => {
    expect(convertSecondsToMinutes(NaN)).toBe("0:00");
  });

  it("handles decimal seconds", () => {
    expect(convertSecondsToMinutes(90.5)).toBe("1:30");
  });
});

describe("calculateTimeRemaining", () => {
  it("returns 0m when time has passed", () => {
    expect(calculateTimeRemaining(100, 200)).toBe("0m");
  });

  it("returns minutes only for short durations", () => {
    const currentTime = 0;
    const startTime = 1800; // 30 minutes
    expect(calculateTimeRemaining(startTime, currentTime)).toBe("30m");
  });

  it("returns hours and minutes", () => {
    const currentTime = 0;
    const startTime = 3660; // 1 hour and 1 minute
    expect(calculateTimeRemaining(startTime, currentTime)).toBe("1h 1m");
  });

  it("returns days, hours, and minutes", () => {
    const currentTime = 0;
    const startTime = 90060; // 1 day, 1 hour, and 1 minute
    expect(calculateTimeRemaining(startTime, currentTime)).toBe("1d 1h 1m");
  });

  it("handles exact hour boundaries", () => {
    const currentTime = 0;
    const startTime = 3600; // exactly 1 hour
    expect(calculateTimeRemaining(startTime, currentTime)).toBe("1h 0m");
  });
});

describe("convertUnixToLocalTime", () => {
  it("converts unix timestamp to date string", () => {
    // Jan 1, 2024 00:00:00 UTC
    const timestamp = 1704067200;
    expect(convertUnixToLocalTime(timestamp)).toBe("01/01/2024");
  });

  it("handles different dates", () => {
    // Dec 25, 2023 00:00:00 UTC
    const timestamp = 1703462400;
    expect(convertUnixToLocalTime(timestamp)).toBe("12/25/2023");
  });
});

describe("formatToken", () => {
  it("formats token with default decimals", () => {
    const amount = BigInt("1000000000000000000"); // 1 token with 18 decimals
    expect(formatToken(amount)).toBe("1.00");
  });

  it("formats token with custom decimals", () => {
    const amount = BigInt("1000000"); // 1 token with 6 decimals
    expect(formatToken(amount, 6)).toBe("1.00");
  });

  it("formats large amounts", () => {
    const amount = BigInt("1234567890000000000000"); // 1234.56789 with 18 decimals
    expect(formatToken(amount)).toBe("1,234.57");
  });

  it("formats small amounts", () => {
    const amount = BigInt("10000000000000000"); // 0.01 with 18 decimals
    expect(formatToken(amount)).toBe("0.01");
  });
});
