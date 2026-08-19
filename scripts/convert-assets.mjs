import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { constants as fsConstants, lstatSync, readFileSync, realpathSync } from "node:fs";
import { chmod, mkdir, mkdtemp, open, readFile, readdir, rename, rm, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

import { stageLockedItem } from "./asset-conversion-staging.mjs";
import { validateAssetLockValue } from "./validate-assets-lock.mjs";
import { validateToolchainLock } from "./validate-toolchain-lock.mjs";

const PROJECT_ROOT = realpathSync(resolve(dirname(fileURLToPath(import.meta.url)), ".."));
const ASSET_LOCK_PATH = join(PROJECT_ROOT, "docs/assets/quaternius-lock.json");
const TOOLCHAIN_LOCK_PATH = join(PROJECT_ROOT, "docs/toolchain-lock.json");
const EXPORTER_PATH = join(PROJECT_ROOT, "scripts/blender/export_selected_glb.py");
const UID = typeof process.getuid === "function" ? process.getuid() : null;
const CLOSED_IDS = new Set(["tank2", "1story", "1story-gable-roof", "2story", "2story-slim", "2story-wide", "3story-small", "4story", "6story-stack"]);
const HELP = "Usage: node scripts/convert-assets.mjs --help | --check | --output-root <absolute-path> (--item <model-id> | --all)\n";

export class ConversionError extends Error {
  constructor(code) { super(code); this.name = "ConversionError"; this.code = code; }
}
const fail = (code) => { throw new ConversionError(code); };
const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
const isInside = (child, parent) => {
  const rel = relative(parent, child);
  return rel === "" || (!rel.startsWith(`..${sep}`) && rel !== ".." && !isAbsolute(rel));
};

function assertAncestors(path, code) {
  for (let cursor = path;; cursor = dirname(cursor)) {
    try { if (lstatSync(cursor).isSymbolicLink()) fail(code); } catch (error) { if (error instanceof ConversionError) throw error; }
    if (dirname(cursor) === cursor) return;
  }
}
function assertPrivateDirectory(path, code) {
  if (typeof path !== "string" || !isAbsolute(path) || resolve(path) !== path || isInside(path, PROJECT_ROOT)) fail(code);
  assertAncestors(path, code);
  let stats;
  try { stats = lstatSync(path); } catch { fail(code); }
  if (!stats.isDirectory() || stats.isSymbolicLink() || (UID !== null && stats.uid !== UID) || (stats.mode & 0o777) !== 0o700) fail(code);
}
function assertPrivateFile(path, code) {
  let stats;
  try { stats = lstatSync(path); } catch { fail(code); }
  if (!stats.isFile() || stats.isSymbolicLink() || (UID !== null && stats.uid !== UID) || stats.nlink !== 1 || (stats.mode & 0o022) !== 0) fail(code);
  return stats;
}
function assertRegularFile(path, code) {
  let stats;
  try { stats = lstatSync(path); } catch { fail(code); }
  if (!stats.isFile() || stats.isSymbolicLink()) fail(code);
  return stats;
}
function canonicalPath(value, code) {
  if (typeof value !== "string" || !isAbsolute(value) || resolve(value) !== value) fail(code);
  try { const resolved = realpathSync(value); if (resolved !== value) fail(code); return resolved; } catch (error) { if (error instanceof ConversionError) throw error; fail(code); }
}

export function parseCliArgs(args) {
  if (!Array.isArray(args)) fail("USAGE");
  if (args.length === 1 && args[0] === "--help") return { mode: "help" };
  if (args.length === 1 && args[0] === "--check") return { mode: "check" };
  if (args.length !== 3 && args.length !== 4) fail("USAGE");
  const outputIndex = args.indexOf("--output-root");
  const itemIndex = args.indexOf("--item");
  const allIndex = args.indexOf("--all");
  if (args.filter((value) => value === "--output-root").length !== 1 || args.filter((value) => value === "--item").length > 1 || args.filter((value) => value === "--all").length > 1) fail("USAGE");
  if (outputIndex === -1 || outputIndex + 1 >= args.length || (itemIndex === -1) === (allIndex === -1) || (allIndex > -1 && args.length !== 3)) fail("USAGE");
  if (itemIndex > -1 && (itemIndex + 1 >= args.length || args.length !== 4)) fail("USAGE");
  const known = new Set(["--output-root", "--item", "--all"]);
  for (let index = 0; index < args.length; index += 1) {
    if (index === outputIndex + 1 || index === itemIndex + 1) continue;
    if (!known.has(args[index])) fail("USAGE");
  }
  const outputRoot = args[outputIndex + 1];
  if (typeof outputRoot !== "string" || !isAbsolute(outputRoot) || resolve(outputRoot) !== outputRoot) fail("USAGE");
  return itemIndex > -1 ? { mode: "run", outputRoot, itemId: args[itemIndex + 1] } : { mode: "run", outputRoot, all: true };
}

export function logicalOutputPath(model) {
  if (model === null || typeof model !== "object" || !CLOSED_IDS.has(model.id)) fail("MODEL_ID_INVALID");
  if (model.category === "tank" && model.id === "tank2") return `assets/models/tank/${model.id}.glb`;
  if (model.category === "building" && model.id !== "tank2") return `assets/models/buildings/${model.id}.glb`;
  fail("MODEL_CATEGORY_INVALID");
}
export function canonicalJson(value) {
  if (value === undefined || typeof value === "function" || typeof value === "symbol" || (typeof value === "number" && !Number.isFinite(value))) fail("CANONICAL_VALUE_INVALID");
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (value !== null && typeof value === "object") return `{${Object.keys(value).sort((left, right) => Buffer.from(left, "utf8").compare(Buffer.from(right, "utf8"))).map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  return JSON.stringify(value);
}
export function canonicalBytes(value) { return Buffer.from(`${canonicalJson(value)}\n`, "utf8"); }

function loadCommittedLocks(read = readFileSync) {
  let assetBytes; let toolchainBytes;
  try { assetBytes = read(ASSET_LOCK_PATH); toolchainBytes = read(TOOLCHAIN_LOCK_PATH); } catch { fail("LOCK_IO"); }
  try {
    return {
      asset: validateAssetLockValue(JSON.parse(assetBytes.toString("utf8"))),
      toolchain: validateToolchainLock(JSON.parse(toolchainBytes.toString("utf8"))),
      assetDigest: sha256(assetBytes), toolchainDigest: sha256(toolchainBytes),
    };
  } catch { fail("LOCK_INVALID"); }
}
function getBlender(toolchain) {
  const blender = toolchain.tools.find((tool) => tool.id === "blender");
  if (blender === undefined) fail("TOOLCHAIN_INVALID");
  return blender;
}
export function resolveBlenderExecutable(toolchain, environment = process.env) {
  const blender = getBlender(toolchain);
  const explicit = environment.BLENDER_BIN;
  if (typeof explicit === "string" && explicit.length > 0) return canonicalPath(explicit, "BLENDER_INVALID");
  const cacheRoot = typeof environment.TANK_SKIRMISH_TOOL_CACHE === "string" && environment.TANK_SKIRMISH_TOOL_CACHE.length > 0
    ? canonicalPath(environment.TANK_SKIRMISH_TOOL_CACHE, "BLENDER_INVALID")
    : join(homedir(), ".cache", "tank-skirmish", "toolchains");
  assertAncestors(cacheRoot, "BLENDER_INVALID");
  return join(cacheRoot, ...blender.install.cacheRelativePath.split("/"), ...blender.install.executableRelativePath.split("/"));
}
export function verifyBlenderExecutable(path, blender, runProcess = (executable, args) => spawnSync(executable, args, { encoding: "utf8", shell: false })) {
  assertPrivateFile(path, "BLENDER_INVALID");
  let bytes;
  try { bytes = readFileSync(path); } catch { fail("BLENDER_INVALID"); }
  if (sha256(bytes) !== blender.install.executableChecksum.value) fail("BLENDER_DIGEST_MISMATCH");
  const result = runProcess(path, ["--version"]);
  if (result?.error !== undefined || result?.status !== 0) fail("BLENDER_VERSION_MISMATCH");
  const lines = `${result.stdout ?? ""}`.replace(/\r\n/gu, "\n").split("\n");
  const contract = blender.install.versionContract;
  if (lines[0] !== contract.firstLine || !lines.some((line) => line.trim() === `build hash: ${contract.buildHash}`)) fail("BLENDER_VERSION_MISMATCH");
}
function requestFor(model, staged, outputPath, resultPath) {
  return {
    category: model.category, id: model.id, outputPrivatePath: outputPath, policy: { animation: model.animationPolicy, texture: model.texturePolicy },
    resultPrivatePath: resultPath, scale: staged.scale, sourceBasename: staged.source.basename, atlasBasename: staged.atlas?.basename ?? null,
    atlasDigest: staged.atlas?.digest ?? null,
  };
}
function assertNoSensitiveRequest(request) {
  const text = JSON.stringify(request);
  if (/cache|token|network|home|environment/iu.test(text)) fail("REQUEST_SENSITIVE");
}
async function writePrivateJson(path, value) {
  await writeFile(path, canonicalBytes(value), { mode: 0o600, flag: "wx" });
  await chmod(path, 0o600);
}
async function readResult(path) {
  let value;
  try { value = JSON.parse(await readFile(path, "utf8")); } catch { fail("EXPORT_RESULT_INVALID"); }
  if (value === null || typeof value !== "object" || Array.isArray(value) || Object.keys(value).length !== 1 || !Array.isArray(value.sourceActionNames) || !value.sourceActionNames.every((name) => typeof name === "string")
    || [...value.sourceActionNames].sort().some((name, index) => name !== value.sourceActionNames[index])) fail("EXPORT_RESULT_INVALID");
  return value.sourceActionNames;
}
async function verifyItemOutput({ directory, outputPath, requestPath, resultPath, sourceBasename, atlasBasename }) {
  const expected = new Set([sourceBasename, requestPath === undefined ? "" : basename(requestPath), basename(outputPath), basename(resultPath), ...(atlasBasename === null ? [] : [atlasBasename])]);
  const actual = new Set(await readdir(directory));
  if (actual.size !== expected.size || [...actual].some((name) => !expected.has(name))) fail("EXPORT_OUTPUT_INVALID");
  const output = await open(outputPath, fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW).catch(() => fail("EXPORT_OUTPUT_INVALID"));
  try { const stats = await output.stat(); if (!stats.isFile() || stats.size === 0) fail("EXPORT_OUTPUT_INVALID"); } finally { await output.close(); }
  return sha256(await readFile(outputPath));
}
export function computeRunIdentity({ assetLockDigest, toolchainLockDigest, exporterDigest, models }) {
  return sha256(canonicalBytes({ assetLockDigest, exporterDigest, models: models.map(({ id, sourceDigest, scale, policy, sourceActionNames, outputLogicalPath }) => ({ id, outputLogicalPath, policy, scale, sourceActionNames, sourceDigest })), toolchainLockDigest }));
}

export async function runConversion({ assetLock, toolchainLock, assetLockDigest, toolchainLockDigest, outputRoot, itemIds, environment = process.env, stageItem = stageLockedItem, runProcess, exporterPath = EXPORTER_PATH, blenderPath, releaseRoot, read = readFileSync } = {}) {
  assertPrivateDirectory(outputRoot, "OUTPUT_ROOT_INVALID");
  let exporterBytes;
  try { exporterBytes = read(exporterPath); } catch { fail("EXPORTER_MISSING"); }
  const exporterDigest = sha256(exporterBytes);
  const blender = getBlender(toolchainLock);
  const executable = blenderPath ?? resolveBlenderExecutable(toolchainLock, environment);
  verifyBlenderExecutable(executable, blender, runProcess);
  const selected = assetLock.models.filter((model) => itemIds.includes(model.id));
  if (selected.length !== itemIds.length || selected.some((model) => !CLOSED_IDS.has(model.id))) fail("MODEL_ID_INVALID");
  const logicalPaths = selected.map(logicalOutputPath);
  if (new Set(logicalPaths).size !== logicalPaths.length) fail("OUTPUT_COLLISION");
  for (const reserved of ["assets", "conversion-run-manifest.json"]) { try { lstatSync(join(outputRoot, reserved)); fail("OUTPUT_COLLISION"); } catch (error) { if (error instanceof ConversionError) throw error; } }
  for (const logicalPath of logicalPaths) { try { lstatSync(join(outputRoot, logicalPath)); fail("OUTPUT_COLLISION"); } catch (error) { if (error instanceof ConversionError) throw error; } }
  const stageParent = outputRoot;
  const records = [];
  const stagedItems = [];
  let publication;
  try {
    for (const model of selected) {
      const staged = await stageItem({ lock: assetLock, itemId: model.id, stagingParent: stageParent, environment });
      stagedItems.push(staged);
      const directory = dirname(staged.source.path);
      const privateOutput = join(directory, "converted.glb");
      const privateResult = join(directory, "export-result.json");
      const requestPath = join(directory, "conversion-request.json");
      const request = requestFor(model, staged, privateOutput, privateResult);
      assertNoSensitiveRequest(request);
      await writePrivateJson(requestPath, request);
      const processResult = (runProcess ?? ((executablePath, args) => spawnSync(executablePath, args, { encoding: "utf8", shell: false })))(executable, ["--background", "--factory-startup", "--python", exporterPath, "--", requestPath]);
      if (processResult?.error !== undefined || processResult?.status !== 0) fail("EXPORT_FAILED");
      const outputDigest = await verifyItemOutput({ directory, outputPath: privateOutput, requestPath, resultPath: privateResult, sourceBasename: staged.source.basename, atlasBasename: staged.atlas?.basename ?? null });
      const sourceActionNames = await readResult(privateResult);
      if (model.category === "building" && sourceActionNames.length !== 0) fail("EXPORT_RESULT_INVALID");
      records.push({ directory, staged, privateOutput, model, sourceActionNames, outputDigest, outputLogicalPath: logicalOutputPath(model) });
    }
    const identityModels = records.map((record) => ({ id: record.model.id, sourceDigest: record.model.source.sha256, scale: record.model.scale, policy: { animation: record.model.animationPolicy, texture: record.model.texturePolicy }, sourceActionNames: record.sourceActionNames, outputLogicalPath: record.outputLogicalPath }));
    const runIdentity = computeRunIdentity({ assetLockDigest, toolchainLockDigest, exporterDigest, models: identityModels });
    const manifest = {
      blender: { id: blender.id, version: blender.version, executableChecksum: blender.install.executableChecksum.value, versionContract: blender.install.versionContract },
      exporterSourceDigest: exporterDigest, models: records.map((record) => ({ blender: { id: blender.id, version: blender.version, executableChecksum: blender.install.executableChecksum.value, versionContract: blender.install.versionContract }, category: record.model.category, exporterSourceDigest: exporterDigest, id: record.model.id, output: { digest: record.outputDigest, logicalPath: record.outputLogicalPath }, policy: { animation: record.model.animationPolicy, texture: record.model.texturePolicy }, scale: record.model.scale, source: { digest: record.model.source.sha256, fileId: record.model.source.fileId }, sourceActionNames: record.sourceActionNames })),
      runIdentity, schemaVersion: 1,
    };
    publication = releaseRoot ?? await mkdtemp(join(outputRoot, ".conversion-publish-"));
    await chmod(publication, 0o700); assertPrivateDirectory(publication, "OUTPUT_ROOT_INVALID");
    const assetsRoot = join(publication, "assets");
    for (const record of records) {
      const destination = join(publication, record.outputLogicalPath);
      await mkdir(dirname(destination), { recursive: true, mode: 0o700 });
      await rename(record.privateOutput, destination);
    }
    await writeFile(join(publication, "conversion-run-manifest.json"), canonicalBytes(manifest), { mode: 0o600, flag: "wx" });
    if ((await readdir(publication)).length !== 2 || !lstatSync(assetsRoot).isDirectory()) fail("PUBLISH_INVALID");
    await rename(assetsRoot, join(outputRoot, "assets"));
    await rename(join(publication, "conversion-run-manifest.json"), join(outputRoot, "conversion-run-manifest.json"));
    await rm(publication, { recursive: true, force: false });
    return { manifest, manifestDigest: sha256(canonicalBytes(manifest)) };
  } catch (error) {
    if (publication !== undefined) await rm(publication, { recursive: true, force: true }).catch(() => undefined);
    throw error instanceof ConversionError ? error : new ConversionError("CONVERSION_FAILED");
  } finally { await Promise.allSettled(stagedItems.map((staged) => staged.release())); }
}

export async function runCli(args, { stdout = process.stdout, stderr = process.stderr, environment = process.env } = {}) {
  let parsed;
  try { parsed = parseCliArgs(args); } catch (error) { stderr.write(`${error.code ?? "USAGE"}\n`); return 2; }
  if (parsed.mode === "help") { stdout.write(HELP); return 0; }
  if (parsed.mode === "check") {
    try { const locks = loadCommittedLocks(); assertRegularFile(EXPORTER_PATH, "EXPORTER_MISSING"); getBlender(locks.toolchain); stdout.write("conversion runner check passed\n"); return 0; }
    catch (error) { stderr.write(`${error.code ?? "CHECK_FAILED"}\n`); return 1; }
  }
  try {
    const locks = loadCommittedLocks();
    const itemIds = parsed.all ? locks.asset.models.map((model) => model.id) : [parsed.itemId];
    await runConversion({ assetLock: locks.asset, toolchainLock: locks.toolchain, assetLockDigest: locks.assetDigest, toolchainLockDigest: locks.toolchainDigest, outputRoot: parsed.outputRoot, itemIds, environment });
    return 0;
  } catch (error) { stderr.write(`${error.code ?? "CONVERSION_FAILED"}\n`); return 1; }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exitCode = await runCli(process.argv.slice(2));
