import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { chmod, lstat, mkdir, mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
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
    ["animated-tanks", "Tank\u00002.blend"], ["animated-tanks", "Ta\u006e\u0303k.blend"], ["animated-tanks", "tank2.blend"], ["other", "Tank2.blend"],
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
  await mkdir(source, { mode: 0o700 });
  await rejects(() => stageLockedItem({ lock: data.lock, itemId: data.tank.id, cacheRoot: data.cacheRoot, stagingParent: data.stagingParent }), "SOURCE_MISMATCH");
  await rm(source, { recursive: true });
  await writeFile(source, blendBytes("tank"), { mode: 0o600 });
  await chmod(source, 0o666);
  await rejects(() => stageLockedItem({ lock: data.lock, itemId: data.tank.id, cacheRoot: data.cacheRoot, stagingParent: data.stagingParent }), "SOURCE_MISMATCH");
  await chmod(source, 0o600);
  await writeFile(source, blendBytes("wrong"), { mode: 0o600 });
  await rejects(() => stageLockedItem({ lock: data.lock, itemId: data.tank.id, cacheRoot: data.cacheRoot, stagingParent: data.stagingParent }), "SOURCE_MISMATCH");
  assert.deepEqual((await (await import("node:fs/promises")).readdir(data.stagingParent)).filter((name) => name.startsWith("asset-stage-")), []);
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
});
