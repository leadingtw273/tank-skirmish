import { createHash } from "node:crypto";
import { existsSync, lstatSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, isAbsolute, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

import { validateAssetLockValue } from "./validate-assets-lock.mjs";

const IDS = ["tank2", "1story", "1story-gable-roof", "2story", "2story-slim", "2story-wide", "3story-small", "4story", "6story-stack"];
const BUILDING_IDS = new Set(IDS.slice(1));
const ID_SET = new Set(IDS);
const SHA256 = /^[0-9a-f]{64}$/u;
const GLB_MAGIC = 0x46546c67;
const JSON_CHUNK = 0x4e4f534a;
const BIN_CHUNK = 0x004e4942;
const PROJECT_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const ASSET_LOCK_PATH = join(PROJECT_ROOT, "docs", "assets", "quaternius-lock.json");
const TOOLCHAIN_LOCK_PATH = join(PROJECT_ROOT, "docs", "toolchain-lock.json");
const EXPORTER_PATH = join(PROJECT_ROOT, "scripts", "blender", "export_selected_glb.py");
const HELP = "Usage: node scripts/validate-converted-assets.mjs --help | --inspect --input-root <abs> --runner-manifest <abs> --output-report <abs> | --compose --input-root <abs> --runner-manifest <abs> --static-report <abs> --measurement-report <abs> --lock <abs> --output-manifest <abs> | --check --input-root <abs> --manifest <abs> --lock <abs>\n";

export const CONVERTED_ASSET_ERROR_CODES = new Set([
  "USAGE", "IO", "PATH_INVALID", "CANONICAL_MANIFEST_INVALID", "RUNNER_MANIFEST_INVALID", "STATIC_MANIFEST_INVALID",
  "FINAL_MANIFEST_INVALID", "MEASUREMENT_REPORT_INVALID", "LOCK_INVALID", "OUTPUT_INVALID", "GLB_HEADER_INVALID", "GLB_CHUNK_INVALID", "GLB_JSON_INVALID",
  "GLB_STRUCTURE_INVALID", "DIGEST_MISMATCH", "ID_SET_MISMATCH", "JOIN_MISMATCH", "DUPLICATE_DIGEST",
]);

export class ConvertedAssetError extends Error {
  constructor(code) { super(CONVERTED_ASSET_ERROR_CODES.has(code) ? code : "OUTPUT_INVALID"); this.name = "ConvertedAssetError"; this.code = this.message; }
}

const fail = (code) => { throw new ConvertedAssetError(code); };
const digest = (bytes) => createHash("sha256").update(bytes).digest("hex");
const own = (value, key) => Object.hasOwn(value, key);
const record = (value) => value !== null && typeof value === "object" && !Array.isArray(value) && Object.getPrototypeOf(value) === Object.prototype;
const sortCodePoints = (values) => [...values].sort((left, right) => Buffer.from(left, "utf8").compare(Buffer.from(right, "utf8")));
const safe = (value) => Number.isSafeInteger(value) && !Object.is(value, -0) && value >= 0;
const add = (left, right, code) => {
  if (!safe(left) || !safe(right) || right > Number.MAX_SAFE_INTEGER - left) fail(code);
  return left + right;
};
const multiply = (left, right, code) => {
  if (!safe(left) || !safe(right) || (left !== 0 && right > Math.floor(Number.MAX_SAFE_INTEGER / left))) fail(code);
  return left * right;
};

export function canonicalJson(value) {
  if (value === undefined || typeof value === "function" || typeof value === "symbol" || (typeof value === "number" && !Number.isFinite(value))) fail("CANONICAL_MANIFEST_INVALID");
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (record(value)) return `{${Object.keys(value).sort((left, right) => Buffer.from(left, "utf8").compare(Buffer.from(right, "utf8"))).map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  return JSON.stringify(value);
}
export const canonicalBytes = (value) => Buffer.from(`${canonicalJson(value)}\n`, "utf8");

function exact(value, keys, code) {
  if (!record(value) || Object.keys(value).length !== keys.length || keys.some((key) => !own(value, key))) fail(code);
}
function string(value, code, { empty = false } = {}) {
  if (typeof value !== "string" || (!empty && value.length === 0) || /[\u0000-\u001f\u007f]/u.test(value)) fail(code);
  return value;
}
function sha(value, code) { if (typeof value !== "string" || !SHA256.test(value)) fail(code); return value; }
function index(value, length, code) { if (!safe(value) || value >= length) fail(code); return value; }
function logicalPath(id, category) {
  if (!ID_SET.has(id) || (id === "tank2" ? category !== "tank" : category !== "building")) fail("OUTPUT_INVALID");
  return id === "tank2" ? `assets/models/tank/${id}.glb` : `assets/models/buildings/${id}.glb`;
}
function absolute(value) {
  if (typeof value !== "string" || !isAbsolute(value) || resolve(value) !== value) fail("PATH_INVALID");
  return value;
}
function regular(path, code) {
  let stat;
  try { stat = lstatSync(path); } catch { fail(code); }
  if (!stat.isFile() || stat.isSymbolicLink()) fail(code);
}
function directory(path, code) {
  let stat;
  try { stat = lstatSync(path); } catch { fail(code); }
  if (!stat.isDirectory() || stat.isSymbolicLink()) fail(code);
}
function readJsonCanonical(path, code) {
  regular(path, code);
  let bytes; let value;
  try { bytes = readFileSync(path); value = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)); } catch { fail(code); }
  let canonical;
  try { canonical = canonicalBytes(value); } catch { fail(code); }
  if (!bytes.equals(canonical)) fail("CANONICAL_MANIFEST_INVALID");
  return { bytes, value };
}
function uniqueStrings(values, code, { nonempty = true } = {}) {
  if (!Array.isArray(values)) fail(code);
  const seen = new Set();
  for (const value of values) {
    string(value, code, { empty: !nonempty });
    const key = value.normalize("NFC").toLowerCase();
    if (seen.has(key)) fail(code);
    seen.add(key);
  }
  return values;
}
function uniqueDigests(models, code) {
  const seen = new Set();
  for (const model of models) {
    if (seen.has(model.outputDigest)) fail(code);
    seen.add(model.outputDigest);
  }
}
function sameIdSet(models, code) {
  if (!Array.isArray(models) || models.length !== IDS.length) fail(code);
  const ids = models.map((model) => model?.id);
  if (new Set(ids).size !== IDS.length || IDS.some((id) => !ids.includes(id))) fail(code);
}

export function parseCliArgs(args) {
  if (!Array.isArray(args)) fail("USAGE");
  if (args.length === 1 && args[0] === "--help") return { mode: "help" };
  const modes = args.filter((arg) => arg === "--inspect" || arg === "--compose" || arg === "--check");
  if (modes.length !== 1) fail("USAGE");
  const mode = modes[0].slice(2);
  const expected = mode === "inspect" ? ["--input-root", "--runner-manifest", "--output-report"]
    : mode === "compose" ? ["--input-root", "--runner-manifest", "--static-report", "--measurement-report", "--lock", "--output-manifest"]
      : ["--input-root", "--manifest", "--lock"];
  if (args.length !== 1 + expected.length * 2) fail("USAGE");
  const result = { mode };
  for (const flag of expected) {
    const position = args.indexOf(flag);
    if (position === -1 || args.indexOf(flag, position + 1) !== -1 || position + 1 >= args.length) fail("USAGE");
    result[flag.slice(2).replace(/-([a-z])/gu, (_, letter) => letter.toUpperCase())] = absolute(args[position + 1]);
  }
  for (let offset = 0; offset < args.length; offset += 1) {
    if (args[offset] === modes[0]) continue;
    if (expected.includes(args[offset])) { offset += 1; continue; }
    fail("USAGE");
  }
  return result;
}

function validateRunnerModel(model) {
  exact(model, ["blender", "category", "exporterSourceDigest", "id", "output", "policy", "scale", "source", "sourceActionNames"], "RUNNER_MANIFEST_INVALID");
  string(model.id, "RUNNER_MANIFEST_INVALID");
  if (!ID_SET.has(model.id) || (model.id === "tank2" ? model.category !== "tank" : model.category !== "building")) fail("RUNNER_MANIFEST_INVALID");
  exact(model.output, ["digest", "logicalPath"], "RUNNER_MANIFEST_INVALID");
  sha(model.output.digest, "RUNNER_MANIFEST_INVALID");
  if (model.output.logicalPath !== logicalPath(model.id, model.category)) fail("RUNNER_MANIFEST_INVALID");
  exact(model.policy, ["animation", "texture"], "RUNNER_MANIFEST_INVALID");
  string(model.policy.animation, "RUNNER_MANIFEST_INVALID"); string(model.policy.texture, "RUNNER_MANIFEST_INVALID");
  if (typeof model.scale !== "number" || !Number.isFinite(model.scale) || model.scale <= 0) fail("RUNNER_MANIFEST_INVALID");
  exact(model.source, ["digest", "fileId"], "RUNNER_MANIFEST_INVALID"); sha(model.source.digest, "RUNNER_MANIFEST_INVALID"); string(model.source.fileId, "RUNNER_MANIFEST_INVALID");
  uniqueStrings(model.sourceActionNames, "RUNNER_MANIFEST_INVALID");
  if (BUILDING_IDS.has(model.id) && model.sourceActionNames.length !== 0) fail("RUNNER_MANIFEST_INVALID");
  return model;
}
function validateBlender(value, code) {
  exact(value, ["executableChecksum", "id", "version", "versionContract"], code);
  string(value.id, code); string(value.version, code); sha(value.executableChecksum, code);
  if (!record(value.versionContract)) fail(code);
  return value;
}
export function computeRunIdentity({ assetLockDigest, toolchainLockDigest, exporterDigest, models }) {
  return digest(canonicalBytes({ assetLockDigest, exporterDigest, models: models.map(({ id, sourceDigest, scale, policy, sourceActionNames, outputLogicalPath }) => ({ id, outputLogicalPath, policy, scale, sourceActionNames, sourceDigest })), toolchainLockDigest }));
}
export function readRunnerManifest(path) {
  const { bytes, value } = readJsonCanonical(absolute(path), "RUNNER_MANIFEST_INVALID");
  exact(value, ["blender", "exporterSourceDigest", "models", "runIdentity", "schemaVersion"], "RUNNER_MANIFEST_INVALID");
  if (value.schemaVersion !== 1) fail("RUNNER_MANIFEST_INVALID");
  const blender = validateBlender(value.blender, "RUNNER_MANIFEST_INVALID");
  sha(value.exporterSourceDigest, "RUNNER_MANIFEST_INVALID"); sha(value.runIdentity, "RUNNER_MANIFEST_INVALID");
  sameIdSet(value.models, "RUNNER_MANIFEST_INVALID");
  const models = value.models.map(validateRunnerModel);
  for (const model of models) {
    if (JSON.stringify(model.blender) !== JSON.stringify(blender) || model.exporterSourceDigest !== value.exporterSourceDigest) fail("RUNNER_MANIFEST_INVALID");
  }
  uniqueDigests(models.map((model) => ({ outputDigest: model.output.digest })), "DUPLICATE_DIGEST");
  let assetBytes; let toolchainBytes; let exporterBytes; let assetLock; let toolchain;
  try {
    assetBytes = readFileSync(ASSET_LOCK_PATH); toolchainBytes = readFileSync(TOOLCHAIN_LOCK_PATH); exporterBytes = readFileSync(EXPORTER_PATH);
    assetLock = validateAssetLockValue(JSON.parse(assetBytes.toString("utf8"))); toolchain = JSON.parse(toolchainBytes.toString("utf8"));
  } catch { fail("RUNNER_MANIFEST_INVALID"); }
  if (value.exporterSourceDigest !== digest(exporterBytes)) fail("RUNNER_MANIFEST_INVALID");
  const tool = Array.isArray(toolchain?.tools) ? toolchain.tools.find((candidate) => candidate?.id === "blender") : undefined;
  const expectedBlender = tool?.install?.executableChecksum?.value === undefined ? undefined : { executableChecksum: tool.install.executableChecksum.value, id: tool.id, version: tool.version, versionContract: tool.install.versionContract };
  if (expectedBlender === undefined || canonicalJson(blender) !== canonicalJson(expectedBlender)) fail("RUNNER_MANIFEST_INVALID");
  const lockedById = new Map(assetLock.models.map((model) => [model.id, model]));
  const identityModels = models.map((model) => {
    const locked = lockedById.get(model.id);
    if (locked === undefined || model.source.digest !== locked.source.sha256 || model.source.fileId !== locked.source.fileId || model.scale !== locked.scale
      || model.policy.animation !== locked.animationPolicy || model.policy.texture !== locked.texturePolicy) fail("RUNNER_MANIFEST_INVALID");
    return { id: model.id, outputLogicalPath: model.output.logicalPath, policy: model.policy, scale: model.scale, sourceActionNames: model.sourceActionNames, sourceDigest: model.source.digest };
  });
  const recomputed = computeRunIdentity({ assetLockDigest: digest(assetBytes), toolchainLockDigest: digest(toolchainBytes), exporterDigest: value.exporterSourceDigest, models: identityModels });
  if (value.runIdentity !== recomputed) fail("RUNNER_MANIFEST_INVALID");
  return { bytes, digest: digest(bytes), value, blender, models };
}

function u32(view, offset, code) { if (!safe(offset) || add(offset, 4, code) > view.byteLength) fail(code); return view.getUint32(offset, true); }
function componentBytes(componentType) {
  const size = new Map([[5120, 1], [5121, 1], [5122, 2], [5123, 2], [5125, 4], [5126, 4]]).get(componentType);
  if (size === undefined) fail("GLB_STRUCTURE_INVALID");
  return size;
}
function componentCount(type) {
  const count = new Map([["SCALAR", 1], ["VEC2", 2], ["VEC3", 3], ["VEC4", 4], ["MAT2", 4], ["MAT3", 9], ["MAT4", 16]]).get(type);
  if (count === undefined) fail("GLB_STRUCTURE_INVALID");
  return count;
}
function rangesOverlap(left, right) { return left.start < right.end && right.start < left.end; }
export function parseGlb(bytes) {
  if (!Buffer.isBuffer(bytes) || bytes.length < 20) fail("GLB_HEADER_INVALID");
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (u32(view, 0, "GLB_HEADER_INVALID") !== GLB_MAGIC || u32(view, 4, "GLB_HEADER_INVALID") !== 2 || u32(view, 8, "GLB_HEADER_INVALID") !== bytes.length) fail("GLB_HEADER_INVALID");
  let offset = 12; const chunks = [];
  while (offset < bytes.length) {
    const headerEnd = add(offset, 8, "GLB_CHUNK_INVALID");
    if (headerEnd > bytes.length) fail("GLB_CHUNK_INVALID");
    const length = u32(view, offset, "GLB_CHUNK_INVALID"); const type = u32(view, offset + 4, "GLB_CHUNK_INVALID");
    if (length % 4 !== 0) fail("GLB_CHUNK_INVALID");
    const end = add(headerEnd, length, "GLB_CHUNK_INVALID");
    if (end > bytes.length) fail("GLB_CHUNK_INVALID");
    chunks.push({ type, start: headerEnd, end }); offset = end;
  }
  if (offset !== bytes.length || chunks.length !== 2 || chunks[0].type !== JSON_CHUNK || chunks[1].type !== BIN_CHUNK) fail("GLB_CHUNK_INVALID");
  let json;
  try { json = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes.subarray(chunks[0].start, chunks[0].end))); } catch { fail("GLB_JSON_INVALID"); }
  if (!record(json)) fail("GLB_JSON_INVALID");
  const buffers = json.buffers;
  if (!Array.isArray(buffers) || buffers.length !== 1 || !record(buffers[0]) || own(buffers[0], "uri") || !safe(buffers[0].byteLength) || buffers[0].byteLength > chunks[1].end - chunks[1].start) fail("GLB_STRUCTURE_INVALID");
  const bufferLength = buffers[0].byteLength;
  const views = json.bufferViews ?? [];
  if (!Array.isArray(views)) fail("GLB_STRUCTURE_INVALID");
  const parsedViews = views.map((item) => {
    if (!record(item) || item.buffer !== 0 || !safe(item.byteOffset ?? 0) || !safe(item.byteLength)) fail("GLB_STRUCTURE_INVALID");
    const start = item.byteOffset ?? 0; const end = add(start, item.byteLength, "GLB_STRUCTURE_INVALID");
    if (end > bufferLength || (own(item, "byteStride") && (!safe(item.byteStride) || item.byteStride === 0))) fail("GLB_STRUCTURE_INVALID");
    return { start, end, value: item };
  });
  const accessors = json.accessors ?? [];
  if (!Array.isArray(accessors)) fail("GLB_STRUCTURE_INVALID");
  for (const accessor of accessors) {
    if (!record(accessor) || own(accessor, "sparse") || !safe(accessor.bufferView) || !safe(accessor.byteOffset ?? 0) || !safe(accessor.count)) fail("GLB_STRUCTURE_INVALID");
    const bufferView = parsedViews[index(accessor.bufferView, parsedViews.length, "GLB_STRUCTURE_INVALID")];
    const element = multiply(componentBytes(accessor.componentType), componentCount(accessor.type), "GLB_STRUCTURE_INVALID");
    const stride = bufferView.value.byteStride ?? element;
    if (!safe(stride) || stride < element || stride % componentBytes(accessor.componentType) !== 0) fail("GLB_STRUCTURE_INVALID");
    const preceding = accessor.count === 0 ? 0 : multiply(accessor.count - 1, stride, "GLB_STRUCTURE_INVALID");
    const end = add(add(accessor.byteOffset ?? 0, preceding, "GLB_STRUCTURE_INVALID"), accessor.count === 0 ? 0 : element, "GLB_STRUCTURE_INVALID");
    if (end > bufferView.end - bufferView.start) fail("GLB_STRUCTURE_INVALID");
  }
  const images = json.images ?? [];
  if (!Array.isArray(images)) fail("GLB_STRUCTURE_INVALID");
  const imageRanges = [];
  for (const image of images) {
    if (!record(image) || own(image, "uri") || !safe(image.bufferView) || typeof image.mimeType !== "string") fail("GLB_STRUCTURE_INVALID");
    const selected = parsedViews[index(image.bufferView, parsedViews.length, "GLB_STRUCTURE_INVALID")];
    if (imageRanges.some((range) => rangesOverlap(range, selected))) fail("GLB_STRUCTURE_INVALID");
    imageRanges.push(selected);
  }
  const animations = json.animations ?? [];
  if (!Array.isArray(animations)) fail("GLB_STRUCTURE_INVALID");
  const animationNames = animations.map((animation) => { if (!record(animation)) fail("GLB_STRUCTURE_INVALID"); return string(animation.name, "GLB_STRUCTURE_INVALID"); });
  uniqueStrings(animationNames, "GLB_STRUCTURE_INVALID");
  return { animationNames, imageRanges, imageCount: images.length, bin: bytes.subarray(chunks[1].start, chunks[1].end) };
}

function inspectModel(inputRoot, model) {
  const outputRelativePath = logicalPath(model.id, model.category);
  const absolutePath = join(inputRoot, ...outputRelativePath.split("/"));
  regular(absolutePath, "OUTPUT_INVALID");
  const bytes = readFileSync(absolutePath); const outputDigest = digest(bytes);
  if (outputDigest !== model.output.digest) fail("DIGEST_MISMATCH");
  const glb = parseGlb(bytes);
  const animationNames = sortCodePoints(glb.animationNames); const sourceActionNames = sortCodePoints(model.sourceActionNames);
  if (model.id === "tank2") {
    if (glb.imageCount !== 0 || animationNames.length === 0 || animationNames.length !== sourceActionNames.length || animationNames.some((name, index) => name !== sourceActionNames[index])) fail("GLB_STRUCTURE_INVALID");
    return { id: model.id, category: model.category, outputRelativePath, outputDigest, sourceActionNames, animationNames, imageCount: 0, embeddedImageDigest: null };
  }
  if (sourceActionNames.length !== 0 || animationNames.length !== 0 || glb.imageCount !== 1 || glb.imageRanges.length !== 1) fail("GLB_STRUCTURE_INVALID");
  const image = glb.imageRanges[0];
  return { id: model.id, category: model.category, outputRelativePath, outputDigest, sourceActionNames, animationNames, imageCount: 1, embeddedImageDigest: digest(glb.bin.subarray(image.start, image.end)) };
}
function assertInputTree(root) {
  directory(root, "OUTPUT_INVALID");
  const expectedRoot = new Set(["assets", "conversion-run-manifest.json"]);
  const rootEntries = readdirSync(root);
  if (rootEntries.length !== expectedRoot.size || rootEntries.some((entry) => !expectedRoot.has(entry))) fail("OUTPUT_INVALID");
  const assets = join(root, "assets"); const models = join(assets, "models");
  for (const path of [assets, models, join(models, "tank"), join(models, "buildings")]) directory(path, "OUTPUT_INVALID");
  const expectedTank = new Set(["tank2.glb"]); const expectedBuildings = new Set(IDS.slice(1).map((id) => `${id}.glb`));
  for (const [path, expected] of [[join(models, "tank"), expectedTank], [join(models, "buildings"), expectedBuildings]]) {
    const entries = readdirSync(path); if (entries.length !== expected.size || entries.some((entry) => !expected.has(entry))) fail("OUTPUT_INVALID");
  }
  const modelEntries = readdirSync(models); if (modelEntries.length !== 2 || modelEntries.some((entry) => entry !== "tank" && entry !== "buildings")) fail("OUTPUT_INVALID");
  const assetEntries = readdirSync(assets); if (assetEntries.length !== 1 || assetEntries[0] !== "models") fail("OUTPUT_INVALID");
}
export function inspectConvertedAssets({ inputRoot, runnerManifest } = {}) {
  inputRoot = absolute(inputRoot); runnerManifest = absolute(runnerManifest);
  assertInputTree(inputRoot);
  const runner = readRunnerManifest(runnerManifest);
  if (resolve(runnerManifest) !== join(inputRoot, "conversion-run-manifest.json")) fail("OUTPUT_INVALID");
  const models = IDS.map((id) => inspectModel(inputRoot, runner.models.find((model) => model.id === id)));
  uniqueDigests(models, "DUPLICATE_DIGEST");
  return {
    schemaVersion: 1,
    runIdentity: runner.value.runIdentity,
    runnerManifestDigest: runner.digest,
    toolchain: runner.blender,
    exporter: { sourceDigest: runner.value.exporterSourceDigest },
    models,
  };
}
function validateStaticReport(value, code) {
  exact(value, ["schemaVersion", "runIdentity", "runnerManifestDigest", "toolchain", "exporter", "models"], code);
  if (value.schemaVersion !== 1) fail(code); sha(value.runIdentity, code); sha(value.runnerManifestDigest, code); validateBlender(value.toolchain, code);
  exact(value.exporter, ["sourceDigest"], code); sha(value.exporter.sourceDigest, code); sameIdSet(value.models, code);
  for (const model of value.models) {
    exact(model, ["id", "category", "outputRelativePath", "outputDigest", "sourceActionNames", "animationNames", "imageCount", "embeddedImageDigest"], code);
    if (!ID_SET.has(model.id) || (model.id === "tank2" ? model.category !== "tank" : model.category !== "building") || model.outputRelativePath !== logicalPath(model.id, model.category)) fail(code);
    sha(model.outputDigest, code); uniqueStrings(model.sourceActionNames, code); uniqueStrings(model.animationNames, code);
    if (!safe(model.imageCount)) fail(code);
    if (model.id === "tank2") { if (model.imageCount !== 0 || model.embeddedImageDigest !== null || model.animationNames.length === 0 || JSON.stringify(sortCodePoints(model.animationNames)) !== JSON.stringify(sortCodePoints(model.sourceActionNames))) fail(code); }
    else if (model.imageCount !== 1 || model.embeddedImageDigest === null || (typeof model.embeddedImageDigest !== "string" || !SHA256.test(model.embeddedImageDigest)) || model.sourceActionNames.length !== 0 || model.animationNames.length !== 0) fail(code);
  }
  uniqueDigests(value.models, "DUPLICATE_DIGEST");
  return value;
}
function readStatic(path, code) {
  const { bytes, value } = readJsonCanonical(absolute(path), code); return { bytes, value: validateStaticReport(value, code) };
}
function modelMap(models) { return new Map(models.map((model) => [model.id, model])); }
function validateMeasurementReport(value, code) {
  exact(value, ["schemaVersion", "staticReportDigest", "models"], code);
  if (value.schemaVersion !== 1) fail(code); sha(value.staticReportDigest, code); sameIdSet(value.models, code);
  for (const model of value.models) {
    exact(model, ["id", "outputDigest", "measuredGodotXyz"], code);
    if (!ID_SET.has(model.id)) fail(code); sha(model.outputDigest, code); validateMeasurement(model.measuredGodotXyz, code);
  }
  uniqueDigests(value.models, "DUPLICATE_DIGEST");
  return value;
}
function validateMeasurement(value, code) {
  if (!Array.isArray(value) || value.length !== 3 || value.some((axis) => typeof axis !== "number" || !Number.isFinite(axis))) fail(code);
}
function validateCompositeManifest(value, code) {
  exact(value, ["schemaVersion", "runnerManifestDigest", "runnerRunIdentity", "toolchain", "exporterDigest", "models"], code);
  if (value.schemaVersion !== 1) fail(code);
  sha(value.runnerManifestDigest, code); sha(value.runnerRunIdentity, code); sha(value.exporterDigest, code); validateBlender(value.toolchain, code); sameIdSet(value.models, code);
  for (const model of value.models) {
    exact(model, ["id", "category", "sourceFileId", "sourceDigest", "scale", "sourceActionNames", "outputRelativePath", "outputDigest", "animationNames", "imageCount", "embeddedImageDigest", "measuredGodotXyz"], code);
    if (!ID_SET.has(model.id) || (model.id === "tank2" ? model.category !== "tank" : model.category !== "building")) fail(code);
    string(model.sourceFileId, code); sha(model.sourceDigest, code);
    if (typeof model.scale !== "number" || !Number.isFinite(model.scale) || model.scale <= 0) fail(code);
    if (model.outputRelativePath !== logicalPath(model.id, model.category)) fail(code);
    sha(model.outputDigest, code); uniqueStrings(model.sourceActionNames, code); uniqueStrings(model.animationNames, code); if (!safe(model.imageCount)) fail(code); validateMeasurement(model.measuredGodotXyz, code);
    if (model.id === "tank2") {
      if (model.imageCount !== 0 || model.embeddedImageDigest !== null || model.animationNames.length === 0 || canonicalJson(sortCodePoints(model.animationNames)) !== canonicalJson(sortCodePoints(model.sourceActionNames))) fail(code);
    } else if (model.imageCount !== 1 || !SHA256.test(model.embeddedImageDigest ?? "") || model.sourceActionNames.length !== 0 || model.animationNames.length !== 0) fail(code);
  }
  uniqueDigests(value.models, "DUPLICATE_DIGEST");
  return value;
}
function readComposite(path, code = "FINAL_MANIFEST_INVALID") {
  const { value } = readJsonCanonical(absolute(path), code); return validateCompositeManifest(value, code);
}
function readLock(path) {
  let value;
  try { value = validateAssetLockValue(JSON.parse(readFileSync(absolute(path), "utf8"))); } catch { fail("LOCK_INVALID"); }
  sameIdSet(value.models, "ID_SET_MISMATCH");
  return value;
}
function assertLockMatchesRunner(lockValue, runnerModels) {
  const lockedById = modelMap(lockValue.models);
  for (const runner of runnerModels) {
    const locked = lockedById.get(runner.id);
    if (locked === undefined || runner.source.fileId !== locked.source.fileId || runner.source.digest !== locked.source.sha256 || runner.scale !== locked.scale
      || runner.policy.animation !== locked.animationPolicy || runner.policy.texture !== locked.texturePolicy) fail("JOIN_MISMATCH");
  }
}
function assertAbsentLock(lockValue) {
  if (lockValue.conversionManifest.state !== "absent") return;
  for (const model of lockValue.models) {
    if (model.outputDigest !== null || model.measuredGodotXyz !== null || model.embeddedImageDigest !== null) fail("LOCK_INVALID");
  }
}
function assertPresentLock(lockValue, composite) {
  if (lockValue.conversionManifest.state !== "present") fail("LOCK_INVALID");
  const byId = modelMap(composite.models);
  for (const locked of lockValue.models) {
    const actual = byId.get(locked.id);
    if (actual === undefined || locked.source.fileId !== actual.sourceFileId || locked.source.sha256 !== actual.sourceDigest || locked.scale !== actual.scale
      || locked.outputDigest !== actual.outputDigest || locked.embeddedImageDigest !== actual.embeddedImageDigest
      || canonicalJson(locked.measuredGodotXyz) !== canonicalJson(actual.measuredGodotXyz)) fail("JOIN_MISMATCH");
  }
}
export function composeConvertedAssets({ inputRoot, runnerManifest, staticReport, measurementReport, lock } = {}) {
  inputRoot = absolute(inputRoot); runnerManifest = absolute(runnerManifest);
  assertInputTree(inputRoot);
  if (runnerManifest !== join(inputRoot, "conversion-run-manifest.json")) fail("OUTPUT_INVALID");
  const runner = readRunnerManifest(runnerManifest);
  const inspected = inspectConvertedAssets({ inputRoot, runnerManifest });
  const staticRead = readStatic(staticReport, "STATIC_MANIFEST_INVALID");
  if (!staticRead.bytes.equals(canonicalBytes(inspected)) || canonicalJson(staticRead.value) !== canonicalJson(inspected)) fail("JOIN_MISMATCH");
  const measurementRead = readJsonCanonical(absolute(measurementReport), "MEASUREMENT_REPORT_INVALID");
  const measurement = validateMeasurementReport(measurementRead.value, "MEASUREMENT_REPORT_INVALID");
  if (measurement.staticReportDigest !== digest(staticRead.bytes)) fail("DIGEST_MISMATCH");
  const lockValue = readLock(lock); assertLockMatchesRunner(lockValue, runner.models); assertAbsentLock(lockValue);
  const staticById = modelMap(staticRead.value.models); const measuredById = modelMap(measurement.models);
  const models = IDS.map((id) => {
    const source = runner.models.find((model) => model.id === id); const stat = staticById.get(id); const measured = measuredById.get(id);
    if (source === undefined || stat === undefined || measured === undefined || source.output.digest !== stat.outputDigest || stat.outputDigest !== measured.outputDigest) fail("JOIN_MISMATCH");
    return { id, category: source.category, sourceFileId: source.source.fileId, sourceDigest: source.source.digest, scale: source.scale, sourceActionNames: sortCodePoints(source.sourceActionNames), outputRelativePath: stat.outputRelativePath, outputDigest: stat.outputDigest, animationNames: stat.animationNames, imageCount: stat.imageCount, embeddedImageDigest: stat.embeddedImageDigest, measuredGodotXyz: measured.measuredGodotXyz };
  });
  const composite = { schemaVersion: 1, runnerManifestDigest: staticRead.value.runnerManifestDigest, runnerRunIdentity: staticRead.value.runIdentity, toolchain: staticRead.value.toolchain, exporterDigest: staticRead.value.exporter.sourceDigest, models };
  validateCompositeManifest(composite, "FINAL_MANIFEST_INVALID");
  if (composite.runnerManifestDigest !== runner.digest || composite.runnerRunIdentity !== runner.value.runIdentity || canonicalJson(composite.toolchain) !== canonicalJson(runner.blender) || composite.exporterDigest !== runner.value.exporterSourceDigest) fail("JOIN_MISMATCH");
  if (lockValue.conversionManifest.state === "present") assertPresentLock(lockValue, composite);
  return composite;
}
function assertProductionGlbTree(root) {
  directory(root, "OUTPUT_INVALID");
  const models = join(root, "assets", "models"); const tank = join(models, "tank"); const buildings = join(models, "buildings");
  for (const path of [models, tank, buildings]) directory(path, "OUTPUT_INVALID");
  const expected = [[tank, new Set(["tank2.glb"])], [buildings, new Set(IDS.slice(1).map((id) => `${id}.glb`) )]];
  for (const [path, names] of expected) {
    const entries = readdirSync(path); const glbs = entries.filter((entry) => entry.endsWith(".glb"));
    if (glbs.length !== names.size || glbs.some((entry) => !names.has(entry))) fail("OUTPUT_INVALID");
  }
}
function inspectProductionAssets(inputRoot, composite) {
  assertProductionGlbTree(inputRoot);
  const models = IDS.map((id) => {
    const model = modelMap(composite.models).get(id);
    return inspectModel(inputRoot, { ...model, output: { digest: model.outputDigest } });
  });
  uniqueDigests(models, "DUPLICATE_DIGEST");
  return models;
}
export function checkConvertedAssets({ inputRoot, manifest, lock } = {}) {
  inputRoot = absolute(inputRoot);
  const composite = readComposite(manifest); const lockValue = readLock(lock); assertPresentLock(lockValue, composite);
  const current = inspectProductionAssets(inputRoot, composite); const byId = modelMap(composite.models);
  for (const item of current) {
    const recorded = byId.get(item.id);
    if (recorded === undefined || item.outputDigest !== recorded.outputDigest || item.outputRelativePath !== recorded.outputRelativePath || item.category !== recorded.category
      || canonicalJson(item.sourceActionNames) !== canonicalJson(recorded.sourceActionNames) || canonicalJson(item.animationNames) !== canonicalJson(recorded.animationNames)
      || item.imageCount !== recorded.imageCount || item.embeddedImageDigest !== recorded.embeddedImageDigest) fail("JOIN_MISMATCH");
  }
  return composite;
}
export async function runCli(args, { stdout = process.stdout, stderr = process.stderr } = {}) {
  let parsed;
  try { parsed = parseCliArgs(args); } catch (error) { stderr.write(`${error.code ?? "USAGE"}\n`); return 2; }
  if (parsed.mode === "help") { stdout.write(HELP); return 0; }
  try {
    if (parsed.mode === "inspect") {
      const report = inspectConvertedAssets({ inputRoot: parsed.inputRoot, runnerManifest: parsed.runnerManifest });
      writeFileSync(parsed.outputReport, canonicalBytes(report), { flag: "wx" });
      return 0;
    }
    if (parsed.mode === "compose") {
      if (existsSync(parsed.outputManifest)) fail("OUTPUT_INVALID");
      const composite = composeConvertedAssets(parsed);
      writeFileSync(parsed.outputManifest, canonicalBytes(composite), { flag: "wx" });
      return 0;
    }
    checkConvertedAssets(parsed); return 0;
  } catch (error) { stderr.write(`${error instanceof ConvertedAssetError ? error.code : "OUTPUT_INVALID"}\n`); return 1; }
}
if (process.argv[1] !== undefined && resolve(process.argv[1]) === new URL(import.meta.url).pathname) process.exitCode = await runCli(process.argv.slice(2));
