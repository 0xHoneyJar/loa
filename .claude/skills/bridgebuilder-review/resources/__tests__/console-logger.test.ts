import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { ConsoleLogger } from "../adapters/console-logger.js";

describe("ConsoleLogger", () => {
  let captured: string[] = [];
  const originalLog = console.log;
  const originalError = console.error;

  beforeEach(() => {
    captured = [];
    console.log = (...args: unknown[]) => {
      captured.push(args.map(String).join(" "));
    };
    console.error = (...args: unknown[]) => {
      captured.push(args.map(String).join(" "));
    };
  });

  afterEach(() => {
    console.log = originalLog;
    console.error = originalError;
  });

  it("logs structured JSON with level and message", () => {
    const logger = new ConsoleLogger();
    logger.info("test message");
    assert.equal(captured.length, 1);
    const entry = JSON.parse(captured[0]);
    assert.equal(entry.level, "info");
    assert.equal(entry.message, "test message");
    assert.ok(entry.timestamp);
  });

  it("includes data when provided", () => {
    const logger = new ConsoleLogger();
    logger.info("with data", { key: "value" });
    const entry = JSON.parse(captured[0]);
    assert.equal(entry.data.key, "value");
  });

  it("redacts GitHub PATs from messages", () => {
    const logger = new ConsoleLogger();
    logger.info("token ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn found");
    const entry = JSON.parse(captured[0]);
    assert.ok(entry.message.includes("[REDACTED]"));
    assert.ok(!entry.message.includes("ghp_"));
  });

  it("redacts secrets from data values", () => {
    const logger = new ConsoleLogger();
    logger.info("check", { token: "sk-ant-abcdefghijklmnopqrst" });
    const entry = JSON.parse(captured[0]);
    const dataStr = JSON.stringify(entry.data);
    assert.ok(dataStr.includes("[REDACTED]"));
    assert.ok(!dataStr.includes("sk-ant-"));
  });

  it("uses console.error for error level", () => {
    const logger = new ConsoleLogger();
    logger.error("failure");
    assert.equal(captured.length, 1);
    const entry = JSON.parse(captured[0]);
    assert.equal(entry.level, "error");
  });

  it("supports all log levels", () => {
    const logger = new ConsoleLogger();
    logger.debug("d");
    logger.info("i");
    logger.warn("w");
    logger.error("e");
    assert.equal(captured.length, 4);
    const levels = captured.map((c) => JSON.parse(c).level);
    assert.deepEqual(levels, ["debug", "info", "warn", "error"]);
  });
});
