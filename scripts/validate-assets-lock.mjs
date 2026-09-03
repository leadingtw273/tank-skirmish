import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT_FIELDS = ["schemaVersion", "coordinateContract", "conversionManifest", "models", "atlases"];
const COORDINATE_FIELDS = ["source", "target", "expectedGodotXyzFormula", "axisTolerance"];
const TOLERANCE_FIELDS = ["minimumMeters", "relative"];
const MANIFEST_FIELDS = ["state", "requiredModelFieldsWhenPresent", "requirementsWhenPresent"];
const REQUIREMENTS_FIELDS = ["outputDigest", "measuredGodotXyz", "embeddedImageDigest"];
const MODEL_FIELDS = ["id", "category", "pack", "source", "scale", "rawSourceXyz", "expectedGodotXyz", "animationPolicy", "texturePolicy", "sourceImagePath", "expectedImageCount", "outputDigest", "measuredGodotXyz", "embeddedImageDigest"];
const SOURCE_FIELDS = ["fileId", "filename", "sizeBytes", "sha256"];
const ATLAS_FIELDS = ["id", "pack", "fileId", "filename", "sizeBytes", "sha256", "stagingBasename"];
const SHA256 = /^[0-9a-f]{64}$/u;
const FILE_ID = /^[A-Za-z0-9_-]{33}$/u;
const BASENAME = /^[A-Za-z0-9][A-Za-z0-9._-]*$/u;
const REQUIRED_PRESENT_FIELDS = ["outputDigest", "measuredGodotXyz", "embeddedImageDigest"];
const PRESENT_REQUIREMENTS = {
  outputDigest: "non-null for every model",
  measuredGodotXyz: "non-null for every model",
  embeddedImageDigest: "non-null for every building and null for every tank",
};
const TANK_IDS = new Set(["tank1", "tank2", "tank3", "tank4"]);

function fail(path) {
  throw new Error(path || "root");
}

function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value) && Object.getPrototypeOf(value) === Object.prototype;
}

function pathOf(parent, field) {
  return parent === "" ? field : `${parent}.${field}`;
}

function assertExactFields(value, fields, path) {
  if (!isRecord(value)) fail(path || "root");
  for (const field of fields) {
    if (!Object.hasOwn(value, field)) fail(pathOf(path, field));
  }
  for (const field of Object.keys(value)) {
    if (!fields.includes(field)) fail(pathOf(path, field));
  }
}

function assertString(value, path) {
  if (typeof value !== "string" || value.length === 0 || value.trim() !== value || /[\u0000-\u001F\u007F\u2028\u2029]/u.test(value)) fail(path);
}

function assertFinitePositive(value, path) {
  if (typeof value !== "number" || !Number.isFinite(value) || Object.is(value, -0) || value <= 0) fail(path);
}

function assertSafeInteger(value, path) {
  if (!Number.isSafeInteger(value) || Object.is(value, -0) || value <= 0) fail(path);
}

function assertNonNegativeSafeInteger(value, path) {
  if (!Number.isSafeInteger(value) || Object.is(value, -0) || value < 0) fail(path);
}

function assertDigest(value, path) {
  if (typeof value !== "string" || !SHA256.test(value)) fail(path);
}

function assertFileId(value, path) {
  if (typeof value !== "string" || !FILE_ID.test(value)) fail(path);
}

function assertBasename(value, extension, path) {
  assertString(value, path);
  if (!BASENAME.test(value) || !value.endsWith(extension)) fail(path);
}

function assertVector(value, path) {
  if (!Array.isArray(value) || value.length !== 3) fail(path);
  for (const [index, coordinate] of value.entries()) assertFinitePositive(coordinate, `${path}[${index}]`);
}

function collisionKey(value) {
  return value.normalize("NFC").toLowerCase();
}

function assertUnique(values, path) {
  const seen = new Set();
  for (const [index, value] of values.entries()) {
    const key = collisionKey(value);
    if (seen.has(key)) fail(`${path}[${index}]`);
    seen.add(key);
  }
}

function validateSource(value, path) {
  assertExactFields(value, SOURCE_FIELDS, path);
  assertFileId(value.fileId, pathOf(path, "fileId"));
  assertBasename(value.filename, ".blend", pathOf(path, "filename"));
  assertSafeInteger(value.sizeBytes, pathOf(path, "sizeBytes"));
  assertDigest(value.sha256, pathOf(path, "sha256"));
}

function validateCoordinateContract(value) {
  assertExactFields(value, COORDINATE_FIELDS, "coordinateContract");
  if (value.source !== "blender_xyz") fail("coordinateContract.source");
  if (value.target !== "godot_xyz") fail("coordinateContract.target");
  if (value.expectedGodotXyzFormula !== "round([rawX * scale, rawZ * scale, rawY * scale], 5)") fail("coordinateContract.expectedGodotXyzFormula");
  assertExactFields(value.axisTolerance, TOLERANCE_FIELDS, "coordinateContract.axisTolerance");
  if (value.axisTolerance.minimumMeters !== 0.01) fail("coordinateContract.axisTolerance.minimumMeters");
  if (value.axisTolerance.relative !== 0.01) fail("coordinateContract.axisTolerance.relative");
}

function validateManifest(value) {
  assertExactFields(value, MANIFEST_FIELDS, "conversionManifest");
  if (value.state !== "absent" && value.state !== "present") fail("conversionManifest.state");
  if (!Array.isArray(value.requiredModelFieldsWhenPresent) || value.requiredModelFieldsWhenPresent.length !== REQUIRED_PRESENT_FIELDS.length || value.requiredModelFieldsWhenPresent.some((field, index) => field !== REQUIRED_PRESENT_FIELDS[index])) fail("conversionManifest.requiredModelFieldsWhenPresent");
  assertExactFields(value.requirementsWhenPresent, REQUIREMENTS_FIELDS, "conversionManifest.requirementsWhenPresent");
  for (const field of REQUIREMENTS_FIELDS) {
    if (value.requirementsWhenPresent[field] !== PRESENT_REQUIREMENTS[field]) fail(`conversionManifest.requirementsWhenPresent.${field}`);
  }
}

function validateModel(model, index, manifestState, atlas) {
  const path = `models[${index}]`;
  assertExactFields(model, MODEL_FIELDS, path);
  assertString(model.id, `${path}.id`);
  if (model.category !== "tank" && model.category !== "building") fail(`${path}.category`);
  if (model.pack !== "animated-tanks" && model.pack !== "ultimate-buildings") fail(`${path}.pack`);
  validateSource(model.source, `${path}.source`);
  assertFinitePositive(model.scale, `${path}.scale`);
  assertVector(model.rawSourceXyz, `${path}.rawSourceXyz`);
  assertVector(model.expectedGodotXyz, `${path}.expectedGodotXyz`);
  assertString(model.animationPolicy, `${path}.animationPolicy`);
  assertString(model.texturePolicy, `${path}.texturePolicy`);
  assertNonNegativeSafeInteger(model.expectedImageCount, `${path}.expectedImageCount`);

  const expected = [model.rawSourceXyz[0] * model.scale, model.rawSourceXyz[2] * model.scale, model.rawSourceXyz[1] * model.scale].map((coordinate) => Math.round(coordinate * 100000) / 100000);
  for (const [axis, coordinate] of model.expectedGodotXyz.entries()) {
    if (!Object.is(coordinate, expected[axis])) fail(`${path}.expectedGodotXyz[${axis}]`);
  }

  if (model.category === "tank") {
    if (!TANK_IDS.has(model.id) || model.pack !== "animated-tanks" || model.scale !== 0.45 || model.animationPolicy !== "retain_names_for_future_validation" || model.texturePolicy !== "material_color_only" || model.sourceImagePath !== null || model.expectedImageCount !== 0) fail(path);
  } else if (model.pack !== "ultimate-buildings" || model.scale !== 3.6 || model.animationPolicy !== "no_source_clips" || model.texturePolicy !== "embed_selected_atlas" || model.sourceImagePath !== `//${atlas.stagingBasename}` || model.expectedImageCount !== 1) {
    fail(path);
  }

  if (model.embeddedImageDigest !== null && (model.category === "tank" || manifestState === "absent")) fail(`${path}.embeddedImageDigest`);
  if (manifestState === "absent") {
    if (model.outputDigest !== null) fail(`${path}.outputDigest`);
    if (model.measuredGodotXyz !== null) fail(`${path}.measuredGodotXyz`);
    return;
  }
  assertDigest(model.outputDigest, `${path}.outputDigest`);
  assertVector(model.measuredGodotXyz, `${path}.measuredGodotXyz`);
  for (const [axis, measured] of model.measuredGodotXyz.entries()) {
    if (Math.abs(measured - model.expectedGodotXyz[axis]) > Math.max(0.01, 0.01 * Math.abs(model.expectedGodotXyz[axis]))) fail(`${path}.measuredGodotXyz[${axis}]`);
  }
  if (model.category === "building") assertDigest(model.embeddedImageDigest, `${path}.embeddedImageDigest`);
}

function validateAtlas(atlas, index) {
  const path = `atlases[${index}]`;
  assertExactFields(atlas, ATLAS_FIELDS, path);
  assertString(atlas.id, `${path}.id`);
  if (atlas.pack !== "ultimate-buildings") fail(`${path}.pack`);
  assertFileId(atlas.fileId, `${path}.fileId`);
  assertBasename(atlas.filename, ".png", `${path}.filename`);
  assertSafeInteger(atlas.sizeBytes, `${path}.sizeBytes`);
  assertDigest(atlas.sha256, `${path}.sha256`);
  if (atlas.stagingBasename !== "Texture.png") fail(`${path}.stagingBasename`);
}

export function validateAssetLockValue(value) {
  assertExactFields(value, ROOT_FIELDS, "");
  if (value.schemaVersion !== 1) fail("schemaVersion");
  validateCoordinateContract(value.coordinateContract);
  validateManifest(value.conversionManifest);
  if (!Array.isArray(value.models) || value.models.length !== 12) fail("models");
  if (!Array.isArray(value.atlases) || value.atlases.length !== 1) fail("atlases");
  validateAtlas(value.atlases[0], 0);
  for (const [index, model] of value.models.entries()) validateModel(model, index, value.conversionManifest.state, value.atlases[0]);

  const tanks = value.models.filter((model) => model.category === "tank").length;
  const buildings = value.models.filter((model) => model.category === "building").length;
  if (tanks !== 4 || buildings !== 8) fail("models");
  assertUnique(value.models.map((model) => model.id), "models");
  assertUnique(value.models.map((model) => model.source.filename), "models");
  assertUnique(value.atlases.map((atlas) => atlas.id), "atlases");
  assertUnique(value.atlases.map((atlas) => atlas.filename), "atlases");
  assertUnique(value.atlases.map((atlas) => atlas.stagingBasename), "atlases");
  return value;
}

export function validateAssetLockText(text) {
  if (typeof text !== "string" || text.length === 0 || text.startsWith("\uFEFF")) fail("text");
  let value;
  try {
    value = JSON.parse(text);
  } catch {
    fail("text");
  }
  return validateAssetLockValue(value);
}

function writeJsonLine(stream, value) {
  stream.write(`${JSON.stringify(value)}\n`);
}

export async function runAssetLockCli(args, { lockPath, stdout, stderr }) {
  if (args.length !== 1 || args[0] !== "--check") {
    writeJsonLine(stderr, { ok: false, code: "usage_error", path: "argv" });
    return 2;
  }
  try {
    let source;
    try {
      source = await readFile(lockPath, "utf8");
    } catch {
      writeJsonLine(stderr, { ok: false, code: "io_error", path: "lock" });
      return 1;
    }
    let lock;
    try {
      lock = validateAssetLockText(source);
    } catch (error) {
      const path = error instanceof Error && /^[A-Za-z][A-Za-z0-9.\[\]]*$/u.test(error.message) ? error.message : "lock";
      writeJsonLine(stderr, { ok: false, code: path === "text" ? "parse_error" : "validation_error", path });
      return 1;
    }
    writeJsonLine(stdout, { ok: true, schemaVersion: lock.schemaVersion, models: lock.models.length, atlases: lock.atlases.length });
    return 0;
  } catch (error) {
    writeJsonLine(stderr, { ok: false, code: "unexpected_error", path: "internal" });
    return 1;
  }
}

const scriptPath = fileURLToPath(import.meta.url);
if (process.argv[1] !== undefined && resolve(process.argv[1]) === scriptPath) {
  const lockPath = fileURLToPath(new URL("../docs/assets/quaternius-lock.json", import.meta.url));
  process.exitCode = await runAssetLockCli(process.argv.slice(2), { lockPath, stdout: process.stdout, stderr: process.stderr });
}
