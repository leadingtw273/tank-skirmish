import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { validateToolchainLock } from "../scripts/validate-toolchain-lock.mjs";

const fixture = JSON.parse(
  readFileSync(new URL("../docs/toolchain-lock.json", import.meta.url), "utf8"),
);

function lock() {
  return structuredClone(fixture);
}

function expectPath(mutator, path) {
  const value = lock();
  mutator(value);
  assert.throws(() => validateToolchainLock(value), { message: path });
}

test("accepts the lock and recursively deep-freezes it", () => {
  const value = lock();
  const result = validateToolchainLock(value);

  assert.equal(result, value);
  assert.equal(Object.isFrozen(value), true);
  assert.equal(Object.isFrozen(value.tools), true);
  assert.equal(Object.isFrozen(value.tools[0].archive), true);
  assert.equal(Object.isFrozen(value.tools[0].install.executableChecksum), true);
  assert.throws(() => {
    value.tools[0].version = "mutated";
  }, TypeError);
});

test("rejects root fields, required tool fields, and duplicate tools with stable paths", () => {
  expectPath((value) => {
    value.extra = true;
  }, "extra");
  expectPath((value) => {
    delete value.target;
  }, "target");
  expectPath((value) => {
    value.schemaVersion = 2;
  }, "schemaVersion");
  expectPath((value) => {
    value.target = "darwin-arm64";
  }, "target");
  expectPath((value) => {
    delete value.tools[0].version;
  }, "tools[0].version");
  expectPath((value) => {
    value.tools[0].unknown = true;
  }, "tools[0].unknown");
  expectPath((value) => {
    value.tools[1].id = "godot";
  }, "tools[1].id");
  expectPath((value) => {
    value.tools = [value.tools[0]];
  }, "tools");
});

test("rejects invalid archive and checksum values with field paths", () => {
  expectPath((value) => {
    delete value.tools[0].archive.url;
  }, "tools[0].archive.url");
  expectPath((value) => {
    value.tools[0].archive.extra = true;
  }, "tools[0].archive.extra");
  expectPath((value) => {
    value.tools[0].archive.sizeBytes = 1.5;
  }, "tools[0].archive.sizeBytes");
  expectPath((value) => {
    value.tools[0].archive.memberCount = -1;
  }, "tools[0].archive.memberCount");
  expectPath((value) => {
    value.tools[0].archive.checksum.algorithm = "md5";
  }, "tools[0].archive.checksum.algorithm");
  expectPath((value) => {
    value.tools[0].archive.checksum.value = "A".repeat(128);
  }, "tools[0].archive.checksum.value");
  expectPath((value) => {
    value.tools[0].install.executableChecksum.value = "a".repeat(128);
  }, "tools[0].install.executableChecksum.value");
});

test("rejects unsafe install paths", () => {
  for (const invalidPath of ["/cache", "cache/", "cache//tool", "cache/./tool", "cache/../tool", "cache\\tool", "C:tool", "cache\0tool"]) {
    expectPath((value) => {
      value.tools[0].install.cacheRelativePath = invalidPath;
    }, "tools[0].install.cacheRelativePath");
  }

  expectPath((value) => {
    value.tools[0].install.executableRelativePath = "../Godot";
  }, "tools[0].install.executableRelativePath");
});

test("rejects missing install fields and invalid provenance", () => {
  expectPath((value) => {
    delete value.tools[0].install.executableChecksum;
  }, "tools[0].install.executableChecksum");
  expectPath((value) => {
    value.tools[0].install.unknown = true;
  }, "tools[0].install.unknown");
  expectPath((value) => {
    delete value.tools[0].provenance.verifiedBy;
  }, "tools[0].provenance.verifiedBy");
  expectPath((value) => {
    value.tools[0].provenance.method = "manual";
  }, "tools[0].provenance.method");
  expectPath((value) => {
    value.tools[0].provenance.verifiedAt = "2026-02-30";
  }, "tools[0].provenance.verifiedAt");
  expectPath((value) => {
    value.tools[0].provenance.verifiedBy = "other";
  }, "tools[0].provenance.verifiedBy");
});
