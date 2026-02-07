import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  InMemoryObjectStore,
  createInMemoryObjectStore,
  ObjectStoreSync,
  createObjectStoreSync,
} from "../sync/object-store-sync.js";

describe("ObjectStoreSync (T3.4)", () => {
  // ── InMemoryObjectStore ───────────────────────────

  it("createInMemoryObjectStore returns instance", () => {
    const store = createInMemoryObjectStore();
    assert.ok(store instanceof InMemoryObjectStore);
  });

  it("put/get round-trip", async () => {
    const store = createInMemoryObjectStore();
    const data = Buffer.from("hello");
    await store.put("key1", data);
    const result = await store.get("key1");
    assert.deepEqual(result, data);
  });

  it("get returns null for missing key", async () => {
    const store = createInMemoryObjectStore();
    const result = await store.get("missing");
    assert.equal(result, null);
  });

  it("delete removes key", async () => {
    const store = createInMemoryObjectStore();
    await store.put("k", Buffer.from("v"));
    await store.delete("k");
    assert.equal(await store.get("k"), null);
  });

  it("list returns all keys", async () => {
    const store = createInMemoryObjectStore();
    await store.put("a/1", Buffer.from("1"));
    await store.put("a/2", Buffer.from("2"));
    await store.put("b/1", Buffer.from("3"));
    const all = await store.list();
    assert.equal(all.length, 3);
  });

  it("list filters by prefix", async () => {
    const store = createInMemoryObjectStore();
    await store.put("a/1", Buffer.from("1"));
    await store.put("a/2", Buffer.from("2"));
    await store.put("b/1", Buffer.from("3"));
    const filtered = await store.list("a/");
    assert.equal(filtered.length, 2);
    assert.ok(filtered.every((k) => k.startsWith("a/")));
  });

  // ── ObjectStoreSync ───────────────────────────────

  it("createObjectStoreSync returns instance", () => {
    const local = createInMemoryObjectStore();
    const remote = createInMemoryObjectStore();
    const sync = createObjectStoreSync(local, remote);
    assert.ok(sync instanceof ObjectStoreSync);
  });

  it("push copies local to remote", async () => {
    const local = createInMemoryObjectStore();
    const remote = createInMemoryObjectStore();
    await local.put("file1", Buffer.from("data1"));
    await local.put("file2", Buffer.from("data2"));

    const sync = createObjectStoreSync(local, remote);
    const count = await sync.push();
    assert.equal(count, 2);
    assert.deepEqual(await remote.get("file1"), Buffer.from("data1"));
  });

  it("pull copies remote to local", async () => {
    const local = createInMemoryObjectStore();
    const remote = createInMemoryObjectStore();
    await remote.put("r1", Buffer.from("remote-data"));

    const sync = createObjectStoreSync(local, remote);
    const count = await sync.pull();
    assert.equal(count, 1);
    assert.deepEqual(await local.get("r1"), Buffer.from("remote-data"));
  });

  it("sync returns push and pull counts", async () => {
    const local = createInMemoryObjectStore();
    const remote = createInMemoryObjectStore();
    await local.put("l1", Buffer.from("a"));
    await remote.put("r1", Buffer.from("b"));

    const sync = createObjectStoreSync(local, remote);
    const counts = await sync.sync();
    assert.equal(counts.pushed, 1);
    // After push, remote has l1+r1, so pull copies both to local
    assert.equal(counts.pulled, 2);
    assert.equal(counts.deleted, 0);
  });

  it("push with prefix filters keys", async () => {
    const local = createInMemoryObjectStore();
    const remote = createInMemoryObjectStore();
    await local.put("ns/a", Buffer.from("1"));
    await local.put("other/b", Buffer.from("2"));

    const sync = createObjectStoreSync(local, remote);
    const count = await sync.push("ns/");
    assert.equal(count, 1);
    assert.deepEqual(await remote.get("ns/a"), Buffer.from("1"));
    assert.equal(await remote.get("other/b"), null);
  });
});
