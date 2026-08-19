import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { watch } from "node:fs";
import { chmod, chown, lstat, mkdir, mkdtemp, readFile, readdir, rename, rm, symlink, writeFile } from "node:fs/promises";
import { once } from "node:events";
import { createServer } from "node:net";
import { homedir, tmpdir } from "node:os";
import { join, resolve } from "node:path";
import test from "node:test";

import {
  resolveAssetCacheRoot,
  resolveLockedSourcePath,
  stageLockedItem,
} from "../scripts/asset-conversion-staging.mjs";

const committedLock = JSON.parse(await readFile(new URL("../docs/assets/quaternius-lock.json", import.meta.url), "utf8"));

function digest(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function blendBytes(label) {
  return Buffer.concat([Buffer.from("BLENDER", "ascii"), Buffer.from(` synthetic ${label}`, "utf8")]);
}

function pngBytes(label) {
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), Buffer.from(` synthetic ${label}`, "utf8")]);
}

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), "tank-stage-test-"));
  t.after(async () => { await rm(root, { recursive: true, force: true }); });
  const cacheRoot = join(root, "cache");
  const stagingParent = join(root, "staging");
  await mkdir(cacheRoot, { mode: 0o700 });
  await mkdir(stagingParent, { mode: 0o700 });
  const lock = structuredClone(committedLock);
  const tank = lock.models.find((model) => model.id === "tank2");
  const building = lock.models.find((model) => model.category === "building");
  const atlas = lock.atlases[0];
  const files = [
    [tank.pack, tank.source, blendBytes("tank")],
    [building.pack, building.source, blendBytes("building")],
    [atlas.pack, atlas, pngBytes("atlas")],
  ];
  for (const [pack, entry, bytes] of files) {
    entry.sizeBytes = bytes.length;
    entry.sha256 = digest(bytes);
    const directory = join(cacheRoot, pack);
    await mkdir(directory, { recursive: true, mode: 0o700 });
    await writeFile(join(directory, entry.filename), bytes, { mode: 0o600 });
  }
  return { root, cacheRoot, stagingParent, lock, tank, building, atlas };
}

async function rejects(action, code) {
  await assert.rejects(action, (error) => error?.code === code && error.message === code);
}

async function assertNoStagingDirectory(parent) {
  assert.deepEqual((await readdir(parent)).filter((name) => name.startsWith("asset-stage-")), []);
}

test("cache resolver uses explicit canonical root exclusively and otherwise follows XDG", async (t) => {
  const { root } = await fixture(t);
  const explicit = join(root, "cache");
  assert.equal(resolveAssetCacheRoot({ TANK_SKIRMISH_ASSET_CACHE: explicit, XDG_CACHE_HOME: "/missing" }), explicit);
  assert.equal(resolveAssetCacheRoot({ XDG_CACHE_HOME: root }), join(root, "tank-skirmish", "assets"));
  assert.equal(resolveAssetCacheRoot({}), join(homedir(), ".cache", "tank-skirmish", "assets"));
  assert.throws(() => resolveAssetCacheRoot({ TANK_SKIRMISH_ASSET_CACHE: "relative", XDG_CACHE_HOME: root }), { message: "CACHE_ROOT_INVALID" });
  assert.throws(() => resolveAssetCacheRoot({ TANK_SKIRMISH_ASSET_CACHE: join(root, "missing"), XDG_CACHE_HOME: root }), { message: "CACHE_ROOT_INVALID" });
});

test("locked source paths use only the closed two-segment cache layout", () => {
  const root = resolve(tmpdir(), "tank-stage-layout");
  assert.equal(resolveLockedSourcePath({ pack: "animated-tanks", filename: "Tank2.blend" }, root), join(root, "animated-tanks", "Tank2.blend"));
  for (const [pack, filename] of [
    ["/tmp", "Tank2.blend"], ["animated-tanks", "../Tank2.blend"], ["animated-tanks", "Tank2\\.blend"],
    ["animated-tanks", "Tank\u00002.blend"], ["animated-tanks", "Tank\u00012.blend"], ["animated-tanks", "Ta\u006e\u0303k.blend"], ["animated-tanks", "tank2.blend"], ["other", "Tank2.blend"],
  ]) {
    assert.throws(() => resolveLockedSourcePath({ pack, filename }, root), { message: "INVALID_REQUEST" });
  }
});

test("stages Tank2 through descriptor-bound copy and leaves no directory after release", async (t) => {
  const data = await fixture(t);
  const staged = await stageLockedItem({ lock: data.lock, itemId: data.tank.id, cacheRoot: data.cacheRoot, stagingParent: data.stagingParent });
  assert.equal(staged.itemId, "tank2");
  assert.equal(staged.scale, 0.45);
  assert.equal(staged.atlas, null);
  assert.equal(staged.source.basename, "Tank2.blend");
  assert.notEqual(staged.source.path, join(data.cacheRoot, data.tank.pack, data.tank.source.filename));
  assert.equal((await staged.source.handle.stat()).nlink, 1);
  const directory = resolve(staged.source.path, "..");
  await staged.release();
  await assert.rejects(lstat(directory));
});

test("stages a building and its exact Texture.png atlas output", async (t) => {
  const data = await fixture(t);
  const staged = await stageLockedItem({ lock: data.lock, itemId: data.building.id, cacheRoot: data.cacheRoot, stagingParent: data.stagingParent });
  assert.deepEqual([staged.source.basename, staged.atlas?.basename].sort(), [data.building.source.filename, "Texture.png"].sort());
  assert.equal(await readFile(staged.source.path, "utf8"), (await readFile(join(data.cacheRoot, data.building.pack, data.building.source.filename), "utf8")));
  await staged.release();
});

test("rejects invalid lock, item, repo roots, symlink roots, and symlink sources without success state", async (t) => {
  const data = await fixture(t);
  const invalid = structuredClone(data.lock);
  invalid.models[0].source.filename = "../Tank2.blend";
  await rejects(() => stageLockedItem({ lock: invalid, itemId: data.tank.id, cacheRoot: data.cacheRoot, stagingParent: data.stagingParent }), "LOCK_INVALID");
  await rejects(() => stageLockedItem({ lock: data.lock, itemId: "nope", cacheRoot: data.cacheRoot, stagingParent: data.stagingParent }), "ITEM_NOT_FOUND");
  await rejects(() => stageLockedItem({ lock: data.lock, itemId: data.tank.id, cacheRoot: resolve(".", "tests"), stagingParent: data.stagingParent }), "REPO_PATH_FORBIDDEN");
  const cacheLink = join(data.root, "cache-link");
  await symlink(data.cacheRoot, cacheLink);
  await rejects(() => stageLockedItem({ lock: data.lock, itemId: data.tank.id, cacheRoot: cacheLink, stagingParent: data.stagingParent }), "CACHE_ROOT_INVALID");
  const source = join(data.cacheRoot, data.tank.pack, data.tank.source.filename);
  const target = join(data.cacheRoot, data.tank.pack, "replacement.blend");
  await writeFile(target, blendBytes("replacement"), { mode: 0o600 });
  await rm(source);
  await symlink(target, source);
  await rejects(() => stageLockedItem({ lock: data.lock, itemId: data.tank.id, cacheRoot: data.cacheRoot, stagingParent: data.stagingParent }), "SOURCE_MISMATCH");
});

test("rejects hardlinks, directories, unsafe modes, missing sources, wrong content, and cleans per-run state", async (t) => {
  const data = await fixture(t);
  const source = join(data.cacheRoot, data.tank.pack, data.tank.source.filename);
  const link = join(data.cacheRoot, data.tank.pack, "linked.blend");
  const { link: makeHardlink } = await import("node:fs/promises");
  await makeHardlink(source, link);
  await rm(source);
  await makeHardlink(link, source);
  await rejects(() => stageLockedItem({ lock: data.lock, itemId: data.tank.id, cacheRoot: data.cacheRoot, stagingParent: data.stagingParent }), "SOURCE_MISMATCH");
  await rm(source);
  await rejects(() => stageLockedItem({ lock: data.lock, itemId: data.tank.id, cacheRoot: data.cacheRoot, stagingParent: data.stagingParent }), "SOURCE_MISMATCH");
  await mkdir(source, { mode: 0o700 });
  await rejects(() => stageLockedItem({ lock: data.lock, itemId: data.tank.id, cacheRoot: data.cacheRoot, stagingParent: data.stagingParent }), "SOURCE_MISMATCH");
  await rm(source, { recursive: true });
  await writeFile(source, blendBytes("tank"), { mode: 0o600 });
  await chmod(source, 0o666);
  await rejects(() => stageLockedItem({ lock: data.lock, itemId: data.tank.id, cacheRoot: data.cacheRoot, stagingParent: data.stagingParent }), "SOURCE_MISMATCH");
  await chmod(source, 0o600);
  await writeFile(source, blendBytes("tink"), { mode: 0o600 });
  await rejects(() => stageLockedItem({ lock: data.lock, itemId: data.tank.id, cacheRoot: data.cacheRoot, stagingParent: data.stagingParent }), "SOURCE_MISMATCH");
  await writeFile(source, blendBytes("wrong"), { mode: 0o600 });
  await rejects(() => stageLockedItem({ lock: data.lock, itemId: data.tank.id, cacheRoot: data.cacheRoot, stagingParent: data.stagingParent }), "SOURCE_MISMATCH");
  await assertNoStagingDirectory(data.stagingParent);
});

test("rejects foreign-owned sources when the host permits a wrong-uid fixture", async (t) => {
  if (typeof process.getuid !== "function" || process.getuid() !== 0) {
    t.skip("wrong-uid fixtures require privilege to chown away from the test uid");
    return;
  }
  const data = await fixture(t);
  const source = join(data.cacheRoot, data.tank.pack, data.tank.source.filename);
  await chown(source, 65534, process.getgid?.() ?? 65534);
  await rejects(() => stageLockedItem({ lock: data.lock, itemId: data.tank.id, cacheRoot: data.cacheRoot, stagingParent: data.stagingParent }), "SOURCE_MISMATCH");
  await assertNoStagingDirectory(data.stagingParent);
});

test("rejects missing and invalid atlas before returning a building success state", async (t) => {
  const data = await fixture(t);
  const atlasPath = join(data.cacheRoot, data.atlas.pack, data.atlas.filename);
  await rm(atlasPath);
  await rejects(() => stageLockedItem({ lock: data.lock, itemId: data.building.id, cacheRoot: data.cacheRoot, stagingParent: data.stagingParent }), "ATLAS_INVALID");
  await writeFile(atlasPath, Buffer.from("not a png"), { mode: 0o600 });
  data.atlas.sizeBytes = 9;
  data.atlas.sha256 = digest(Buffer.from("not a png"));
  await rejects(() => stageLockedItem({ lock: data.lock, itemId: data.building.id, cacheRoot: data.cacheRoot, stagingParent: data.stagingParent }), "ATLAS_INVALID");
  await assertNoStagingDirectory(data.stagingParent);
});

test("rejects FIFO sources without blocking or preserving staging state", async (t) => {
  const fifo = await fixture(t);
  const fifoPath = join(fifo.cacheRoot, fifo.tank.pack, fifo.tank.source.filename);
  await rm(fifoPath);
  const mkfifo = spawnSync("mkfifo", [fifoPath], { encoding: "utf8" });
  assert.equal(mkfifo.status, 0, mkfifo.stderr);
  await rejects(() => stageLockedItem({ lock: fifo.lock, itemId: fifo.tank.id, cacheRoot: fifo.cacheRoot, stagingParent: fifo.stagingParent }), "SOURCE_MISMATCH");
  await assertNoStagingDirectory(fifo.stagingParent);
});

test("rejects socket sources when the host permits Unix socket fixtures", async (t) => {
  const socket = await fixture(t);
  const socketPath = join(socket.cacheRoot, socket.tank.pack, socket.tank.source.filename);
  await rm(socketPath);
  const server = createServer();
  try {
    server.listen(socketPath);
    await once(server, "listening");
  } catch (error) {
    if (error?.code === "EPERM" || error?.code === "EACCES") {
      t.skip("Unix socket fixtures are blocked by this sandbox");
      return;
    }
    throw error;
  }
  t.after(() => server.close());
  await rejects(() => stageLockedItem({ lock: socket.lock, itemId: socket.tank.id, cacheRoot: socket.cacheRoot, stagingParent: socket.stagingParent }), "SOURCE_MISMATCH");
  await assertNoStagingDirectory(socket.stagingParent);
});

test("rejects symlink ancestors and unsafe cache or staging parents", async (t) => {
  const data = await fixture(t);
  const cacheParent = join(data.root, "cache-parent");
  await mkdir(cacheParent, { mode: 0o700 });
  const linkedParent = join(data.root, "cache-parent-link");
  await symlink(cacheParent, linkedParent);
  await rejects(() => stageLockedItem({ lock: data.lock, itemId: data.tank.id, cacheRoot: join(linkedParent, "cache"), stagingParent: data.stagingParent }), "CACHE_ROOT_INVALID");

  await chmod(data.cacheRoot, 0o777);
  await rejects(() => stageLockedItem({ lock: data.lock, itemId: data.tank.id, cacheRoot: data.cacheRoot, stagingParent: data.stagingParent }), "CACHE_ROOT_INVALID");
  await chmod(data.cacheRoot, 0o700);
  await chmod(data.stagingParent, 0o770);
  await rejects(() => stageLockedItem({ lock: data.lock, itemId: data.tank.id, cacheRoot: data.cacheRoot, stagingParent: data.stagingParent }), "STAGING_PARENT_INVALID");
  await chmod(data.stagingParent, 0o700);
  await assertNoStagingDirectory(data.stagingParent);
});

test("fails closed when release cannot remove the per-run staging directory", async (t) => {
  const data = await fixture(t);
  const staged = await stageLockedItem({ lock: data.lock, itemId: data.tank.id, cacheRoot: data.cacheRoot, stagingParent: data.stagingParent });
  await chmod(data.stagingParent, 0o500);
  await rejects(() => staged.release(), "CLEANUP_FAILED");
  await chmod(data.stagingParent, 0o700);
  const directory = resolve(staged.source.path, "..");
  assert.notEqual((await lstat(directory)).nlink, 0);
  await rm(directory, { recursive: true, force: true });
  await assertNoStagingDirectory(data.stagingParent);
});

test("cleans an unexpected file injected while descriptor-bound copying is in progress", async (t) => {
  const data = await fixture(t);
  const sourcePath = join(data.cacheRoot, data.tank.pack, data.tank.source.filename);
  const bytes = Buffer.concat([Buffer.from("BLENDER", "ascii"), Buffer.alloc(8 * 1024 * 1024, 0x61)]);
  data.tank.source.sizeBytes = bytes.length;
  data.tank.source.sha256 = digest(bytes);
  await writeFile(sourcePath, bytes, { mode: 0o600 });

  let inject;
  const injected = new Promise((resolveInjection, rejectInjection) => { inject = { resolveInjection, rejectInjection }; });
  let observed = false;
  const watcher = watch(data.stagingParent, (_event, name) => {
    if (observed || typeof name !== "string" || !name.startsWith("asset-stage-")) return;
    observed = true;
    watcher.close();
    writeFile(join(data.stagingParent, name, "unexpected"), "synthetic", { mode: 0o600 })
      .then(inject.resolveInjection, inject.rejectInjection);
  });
  t.after(() => watcher.close());
  const staging = stageLockedItem({ lock: data.lock, itemId: data.tank.id, cacheRoot: data.cacheRoot, stagingParent: data.stagingParent });
  await injected;
  await rejects(() => staging, "STAGING_INVALID");
  await assertNoStagingDirectory(data.stagingParent);
});

test("rejects a source pathname replaced after its destination has opened", async (t) => {
  const data = await fixture(t);
  const sourcePath = join(data.cacheRoot, data.tank.pack, data.tank.source.filename);
  const replacementPath = join(data.cacheRoot, data.tank.pack, "replacement-after-open.blend");
  const bytes = Buffer.concat([Buffer.from("BLENDER", "ascii"), Buffer.alloc(16 * 1024 * 1024, 0x61)]);
  const replacement = Buffer.concat([Buffer.from("BLENDER", "ascii"), Buffer.alloc(16 * 1024 * 1024, 0x62)]);
  data.tank.source.sizeBytes = bytes.length;
  data.tank.source.sha256 = digest(bytes);
  await writeFile(sourcePath, bytes, { mode: 0o600 });
  await writeFile(replacementPath, replacement, { mode: 0o600 });

  let replace;
  const replaced = new Promise((resolveReplacement, rejectReplacement) => { replace = { resolveReplacement, rejectReplacement }; });
  let directoryWatcher;
  const parentWatcher = watch(data.stagingParent, (_event, name) => {
    if (typeof name !== "string" || !name.startsWith("asset-stage-") || directoryWatcher !== undefined) return;
    directoryWatcher = watch(join(data.stagingParent, name), (_destinationEvent, destinationName) => {
      if (destinationName !== data.tank.source.filename) return;
      directoryWatcher.close();
      rename(replacementPath, sourcePath).then(replace.resolveReplacement, replace.rejectReplacement);
    });
  });
  t.after(() => {
    parentWatcher.close();
    directoryWatcher?.close();
  });
  const staging = stageLockedItem({ lock: data.lock, itemId: data.tank.id, cacheRoot: data.cacheRoot, stagingParent: data.stagingParent });
  await replaced;
  await rejects(() => staging, "SOURCE_MISMATCH");
  await assertNoStagingDirectory(data.stagingParent);
});

test("rejects a pre-created staged destination collision and removes the run directory", async (t) => {
  const data = await fixture(t);
  let inject;
  const injected = new Promise((resolveInjection, rejectInjection) => { inject = { resolveInjection, rejectInjection }; });
  let observed = false;
  const watcher = watch(data.stagingParent, (_event, name) => {
    if (observed || typeof name !== "string" || !name.startsWith("asset-stage-")) return;
    observed = true;
    watcher.close();
    writeFile(join(data.stagingParent, name, data.tank.source.filename), blendBytes("collision"), { mode: 0o600 })
      .then(inject.resolveInjection, inject.rejectInjection);
  });
  t.after(() => watcher.close());
  const staging = stageLockedItem({ lock: data.lock, itemId: data.tank.id, cacheRoot: data.cacheRoot, stagingParent: data.stagingParent });
  await injected;
  await rejects(() => staging, "STAGING_INVALID");
  await assertNoStagingDirectory(data.stagingParent);
});
