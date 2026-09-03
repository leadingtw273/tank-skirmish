import { createHash } from "node:crypto";
import { constants as fsConstants, lstatSync, realpathSync } from "node:fs";
import { chmod, mkdtemp, open, readdir, realpath, rm } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from "node:path";

import { validateAssetLockValue } from "./validate-assets-lock.mjs";

const PROJECT_ROOT = realpathSync(resolve(dirname(new URL(import.meta.url).pathname), ".."));
const UID = typeof process.getuid === "function" ? process.getuid() : null;
const PACKS = new Set(["animated-tanks", "ultimate-buildings"]);
const CANONICAL_FILENAMES = new Map([
  ["animated-tanks", new Set(["Tank.blend", "Tank2.blend", "Tank3.blend", "Tank4.blend"])],
  ["ultimate-buildings", new Set([
    "1Story.blend", "1Story_GableRoof.blend", "2Story.blend", "2Story_Slim.blend",
    "2Story_Wide.blend", "3Story_Small.blend", "4Story.blend", "6Story_Stack.blend", "Texture_Light.png",
  ])],
]);
const CONTROL = /[\u0000-\u001F\u007F]/u;
const ERROR_CODES = new Set([
  "INVALID_REQUEST", "LOCK_INVALID", "ITEM_NOT_FOUND", "CACHE_ROOT_INVALID",
  "STAGING_PARENT_INVALID", "REPO_PATH_FORBIDDEN", "SOURCE_INVALID",
  "SOURCE_MISMATCH", "ATLAS_INVALID", "STAGING_INVALID", "CLEANUP_FAILED",
]);

class StagingError extends Error {
  constructor(code) {
    super(ERROR_CODES.has(code) ? code : "STAGING_INVALID");
    this.name = "AssetStagingError";
    this.code = this.message;
  }
}

function fail(code) {
  throw new StagingError(code);
}

function hasUnsafeSegment(value) {
  return typeof value !== "string" || value.length === 0 || CONTROL.test(value)
    || value.includes("/") || value.includes("\\") || value === "." || value === ".."
    || value.normalize("NFC") !== value;
}

function requireCanonicalAbsolute(value, code) {
  if (typeof value !== "string" || !isAbsolute(value) || resolve(value) !== value || CONTROL.test(value)) fail(code);
  return value;
}

function isInside(child, parent) {
  const rel = relative(parent, child);
  return rel === "" || (!rel.startsWith(`..${sep}`) && rel !== ".." && !isAbsolute(rel));
}

function assertOutsideRepository(path, code) {
  if (isInside(path, PROJECT_ROOT)) fail(code);
}

function assertExistingAncestorsNotSymlinks(path, code) {
  let cursor = path;
  for (;;) {
    try {
      if (lstatSync(cursor).isSymbolicLink()) fail(code);
    } catch (error) {
      if (error instanceof StagingError) throw error;
    }
    const parent = dirname(cursor);
    if (parent === cursor) return;
    cursor = parent;
  }
}

function assertPrivateDirectory(path, code) {
  requireCanonicalAbsolute(path, code);
  assertOutsideRepository(path, "REPO_PATH_FORBIDDEN");
  assertExistingAncestorsNotSymlinks(path, code);
  let stats;
  try {
    stats = lstatSync(path);
  } catch {
    fail(code);
  }
  if (!stats.isDirectory() || stats.isSymbolicLink() || (UID !== null && stats.uid !== UID)
    || stats.nlink < 2 || (stats.mode & 0o022) !== 0) fail(code);
}

function assertLockedFilename(pack, filename, code) {
  if (!PACKS.has(pack) || hasUnsafeSegment(pack) || hasUnsafeSegment(filename)
    || basename(filename) !== filename || filename.normalize("NFC") !== filename
    || !CANONICAL_FILENAMES.get(pack)?.has(filename)) fail(code);
}

function entryFrom(value) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) fail("INVALID_REQUEST");
  return value;
}

function expectedMagic(filename) {
  return filename.endsWith(".png") ? Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]) : Buffer.from("BLENDER", "ascii");
}

function hasExpectedMagic(filename, firstBytes) {
  const magic = expectedMagic(filename);
  return firstBytes.length >= magic.length && firstBytes.subarray(0, magic.length).equals(magic);
}

function assertFileStats(stats, expectedSize, code) {
  if (!stats.isFile() || (UID !== null && stats.uid !== UID) || stats.nlink !== 1
    || (stats.mode & 0o022) !== 0 || stats.size !== expectedSize) fail(code);
}

function sameIdentity(a, b) {
  return a.dev === b.dev && a.ino === b.ino;
}

async function assertOpenedSource(path, handle, entry, code) {
  const descriptorStats = await handle.stat();
  assertFileStats(descriptorStats, entry.sizeBytes, code);
  let pathStats;
  try {
    pathStats = lstatSync(path);
  } catch {
    fail(code);
  }
  if (pathStats.isSymbolicLink() || !sameIdentity(descriptorStats, pathStats)) fail(code);
  return descriptorStats;
}

async function copyAndDigest(sourceHandle, destinationHandle, entry, code) {
  const digest = createHash("sha256");
  const first = Buffer.alloc(Math.min(8, entry.sizeBytes));
  let firstLength = 0;
  let position = 0;
  const buffer = Buffer.alloc(64 * 1024);
  for (;;) {
    const { bytesRead } = await sourceHandle.read(buffer, 0, buffer.length, position);
    if (bytesRead === 0) break;
    const chunk = buffer.subarray(0, bytesRead);
    if (firstLength < first.length) {
      const take = Math.min(first.length - firstLength, chunk.length);
      chunk.copy(first, firstLength, 0, take);
      firstLength += take;
    }
    digest.update(chunk);
    if (destinationHandle !== null) {
      let written = 0;
      while (written < chunk.length) {
        const result = await destinationHandle.write(chunk, written, chunk.length - written, position + written);
        if (result.bytesWritten === 0) fail(code);
        written += result.bytesWritten;
      }
    }
    position += bytesRead;
  }
  if (position !== entry.sizeBytes || digest.digest("hex") !== entry.sha256 || !hasExpectedMagic(entry.filename, first.subarray(0, firstLength))) fail(code);
}

async function verifyStagedCopy(path, parent, entry, code) {
  let handle;
  try {
    const canonicalParent = await realpath(parent);
    const canonicalPath = await realpath(path);
    if (!isInside(canonicalPath, canonicalParent) || canonicalPath === canonicalParent) fail(code);
    handle = await open(path, fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW);
    const descriptorStats = await handle.stat();
    const pathStats = lstatSync(path);
    if (pathStats.isSymbolicLink() || !sameIdentity(descriptorStats, pathStats)
      || (descriptorStats.mode & 0o777) !== 0o600) fail(code);
    assertFileStats(descriptorStats, entry.sizeBytes, code);
    await copyAndDigest(handle, null, entry, code);
    return { handle, path: canonicalPath, basename: basename(path) };
  } catch (error) {
    await handle?.close().catch(() => undefined);
    if (error instanceof StagingError) throw error;
    fail(code);
  }
}

async function stageOne({ sourcePath, directory, stagedBasename, entry, sourceCode, stagedCode }) {
  let sourceHandle;
  let destinationHandle;
  try {
    assertExistingAncestorsNotSymlinks(dirname(sourcePath), sourceCode);
    // O_NONBLOCK prevents a hostile FIFO at the locked path from hanging the
    // staging operation before descriptor-bound type validation can reject it.
    sourceHandle = await open(sourcePath, fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW | fsConstants.O_NONBLOCK);
    await assertOpenedSource(sourcePath, sourceHandle, entry, sourceCode);
    const destinationPath = join(directory, stagedBasename);
    try {
      destinationHandle = await open(destinationPath, fsConstants.O_CREAT | fsConstants.O_EXCL | fsConstants.O_WRONLY | fsConstants.O_NOFOLLOW, 0o600);
    } catch {
      fail(stagedCode);
    }
    await copyAndDigest(sourceHandle, destinationHandle, entry, sourceCode);
    // The source descriptor remains authoritative for bytes, but require that
    // the locked pathname still identifies that descriptor before success.
    await assertOpenedSource(sourcePath, sourceHandle, entry, sourceCode);
    await destinationHandle.sync();
    await destinationHandle.close();
    destinationHandle = undefined;
    await sourceHandle.close();
    sourceHandle = undefined;
    return await verifyStagedCopy(destinationPath, directory, entry, stagedCode);
  } catch (error) {
    await destinationHandle?.close().catch(() => undefined);
    await sourceHandle?.close().catch(() => undefined);
    if (error instanceof StagingError) throw error;
    fail(sourceCode);
  }
}

function selectItem(lock, itemId) {
  if (typeof itemId !== "string" || itemId.length === 0) fail("INVALID_REQUEST");
  const item = lock.models.find((model) => model.id === itemId);
  if (item === undefined) fail("ITEM_NOT_FOUND");
  return item;
}

function atlasForItem(lock, item) {
  return item.category === "building" ? lock.atlases[0] : null;
}

function cleanupError(error) {
  return error instanceof StagingError ? error : new StagingError("STAGING_INVALID");
}

export function resolveAssetCacheRoot(environment) {
  if (environment === null || typeof environment !== "object" || Array.isArray(environment)) fail("INVALID_REQUEST");
  const explicit = environment.TANK_SKIRMISH_ASSET_CACHE;
  if (typeof explicit === "string" && explicit.length > 0) {
    requireCanonicalAbsolute(explicit, "CACHE_ROOT_INVALID");
    assertExistingAncestorsNotSymlinks(explicit, "CACHE_ROOT_INVALID");
    try {
      return realpathSync(explicit);
    } catch {
      fail("CACHE_ROOT_INVALID");
    }
  }
  const xdg = environment.XDG_CACHE_HOME;
  const base = typeof xdg === "string" && xdg.length > 0 ? xdg : join(homedir(), ".cache");
  requireCanonicalAbsolute(base, "CACHE_ROOT_INVALID");
  return join(base, "tank-skirmish", "assets");
}

export function resolveLockedSourcePath(lockEntry, cacheRoot) {
  const entry = entryFrom(lockEntry);
  requireCanonicalAbsolute(cacheRoot, "CACHE_ROOT_INVALID");
  assertLockedFilename(entry.pack, entry.filename, "INVALID_REQUEST");
  return join(cacheRoot, entry.pack, entry.filename);
}

export async function stageLockedItem(request) {
  const value = entryFrom(request);
  let lock;
  try {
    lock = validateAssetLockValue(value.lock);
  } catch {
    fail("LOCK_INVALID");
  }
  const item = selectItem(lock, value.itemId);
  const cacheRoot = value.cacheRoot === undefined ? resolveAssetCacheRoot(value.environment ?? process.env) : value.cacheRoot;
  if (typeof value.stagingParent !== "string") fail("INVALID_REQUEST");
  assertPrivateDirectory(cacheRoot, "CACHE_ROOT_INVALID");
  assertPrivateDirectory(value.stagingParent, "STAGING_PARENT_INVALID");
  const atlas = atlasForItem(lock, item);
  const sourceEntry = { pack: item.pack, ...item.source };
  const sourcePath = resolveLockedSourcePath(sourceEntry, cacheRoot);
  const atlasEntry = atlas === null ? null : { ...atlas };
  const atlasPath = atlasEntry === null ? null : resolveLockedSourcePath(atlasEntry, cacheRoot);
  let directory;
  const staged = [];
  try {
    directory = await mkdtemp(join(value.stagingParent, "asset-stage-"));
    await chmod(directory, 0o700);
    assertPrivateDirectory(directory, "STAGING_INVALID");
    const source = await stageOne({
      sourcePath, directory, stagedBasename: item.source.filename, entry: sourceEntry,
      sourceCode: "SOURCE_MISMATCH", stagedCode: "STAGING_INVALID",
    });
    staged.push(source);
    let stagedAtlas = null;
    if (atlasEntry !== null) {
      if (atlasEntry.stagingBasename !== "Texture.png" || atlasEntry.stagingBasename === source.basename) fail("ATLAS_INVALID");
      stagedAtlas = await stageOne({
        sourcePath: atlasPath, directory, stagedBasename: atlasEntry.stagingBasename, entry: atlasEntry,
        sourceCode: "ATLAS_INVALID", stagedCode: "STAGING_INVALID",
      });
      staged.push(stagedAtlas);
    }
    const expected = new Set([item.source.filename, ...(stagedAtlas === null ? [] : [atlasEntry.stagingBasename])]);
    const actual = new Set(await readdir(directory));
    if (expected.size !== staged.length || actual.size !== expected.size || staged.some((file) => !expected.has(file.basename))
      || [...expected].some((name) => !actual.has(name))) fail("STAGING_INVALID");
    return {
      itemId: item.id,
      pack: item.pack,
      source: { fileId: item.source.fileId, digest: item.source.sha256, basename: source.basename, path: source.path, handle: source.handle },
      atlas: stagedAtlas === null ? null : { fileId: atlas.fileId, digest: atlas.sha256, basename: stagedAtlas.basename, path: stagedAtlas.path, handle: stagedAtlas.handle },
      scale: item.scale,
      async release() {
        const results = await Promise.allSettled(staged.map((file) => file.handle.close()));
        try {
          await rm(directory, { recursive: true, force: false });
        } catch {
          fail("CLEANUP_FAILED");
        }
        if (results.some((result) => result.status === "rejected")) fail("CLEANUP_FAILED");
      },
    };
  } catch (error) {
    await Promise.allSettled(staged.map((file) => file.handle.close()));
    if (directory !== undefined) {
      try {
        await rm(directory, { recursive: true, force: false });
      } catch {
        fail("CLEANUP_FAILED");
      }
    }
    throw cleanupError(error);
  }
}
