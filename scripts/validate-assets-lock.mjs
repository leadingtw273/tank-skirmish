import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";

const ROOT_FIELDS = ["schemaVersion", "coordinateContract", "conversionManifest", "models", "atlases"];
const COORDINATE_CONTRACT_FIELDS = ["source", "target", "expectedGodotXyzFormula", "axisTolerance"];
const AXIS_TOLERANCE_FIELDS = ["minimumMeters", "relative"];
const CONVERSION_MANIFEST_FIELDS = ["state", "requiredModelFieldsWhenPresent", "requirementsWhenPresent"];
const REQUIREMENTS_WHEN_PRESENT_FIELDS = ["outputDigest", "measuredGodotXyz", "embeddedImageDigest"];
const MODEL_FIELDS = [
  "id", "category", "pack", "source", "scale", "rawSourceXyz", "expectedGodotXyz",
  "animationPolicy", "texturePolicy", "sourceImagePath", "expectedImageCount", "outputDigest",
  "measuredGodotXyz", "embeddedImageDigest",
];
const SOURCE_FIELDS = ["fileId", "filename", "sizeBytes", "sha256"];
const ATLAS_FIELDS = ["id", "pack", "fileId", "filename", "sizeBytes", "sha256", "stagingBasename"];
const SHA256 = /^[0-9a-f]{64}$/u;
const DRIVE_FILE_ID = /^[A-Za-z0-9_-]{33}$/u;
const SAFE_BASENAME = /^[A-Za-z0-9][A-Za-z0-9._-]*$/u;
const REQUIRED_MODEL_FIELDS_WHEN_PRESENT = ["outputDigest", "measuredGodotXyz", "embeddedImageDigest"];
const REQUIREMENTS_WHEN_PRESENT = {
  outputDigest: "non-null for every model",
  measuredGodotXyz: "non-null for every model",
  embeddedImageDigest: "non-null for every building and null for tank2",
};

function fail(path) {
  throw new Error(path || "root");
}

function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function fieldPath(parent, field) {
  return parent === "" ? field : `${parent}.${field}`;
}

function assertExactFields(value, fields, path) {
  if (!isRecord(value)) {
    fail(path || "root");
  }
  for (const field of fields) {
    if (!Object.hasOwn(value, field)) {
      fail(fieldPath(path, field));
    }
  }
  for (const field of Object.keys(value)) {
    if (!fields.includes(field)) {
      fail(fieldPath(path, field));
    }
  }
}

function assertSafeString(value, path) {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.trim() !== value ||
    /[\u0000-\u001F\u007F\u2028\u2029]/u.test(value)
  ) {
    fail(path);
  }
}

function assertFinitePositive(value, path) {
  if (typeof value !== "number" || !Number.isFinite(value) || Object.is(value, -0) || value <= 0) {
    fail(path);
  }
}

function assertSafePositiveInteger(value, path) {
  if (!Number.isSafeInteger(value) || Object.is(value, -0) || value <= 0) {
    fail(path);
  }
}

function assertSafeNonNegativeInteger(value, path) {
  if (!Number.isSafeInteger(value) || Object.is(value, -0) || value < 0) {
    fail(path);
  }
}

function assertDigest(value, path) {
  if (typeof value !== "string" || !SHA256.test(value)) {
    fail(path);
  }
}

function assertFilename(value, path, extension) {
  assertSafeString(value, path);
  if (!SAFE_BASENAME.test(value) || !value.endsWith(extension)) {
    fail(path);
  }
}

function assertVector(value, path) {
  if (!Array.isArray(value) || value.length !== 3) {
    fail(path);
  }
  value.forEach((axis, index) => assertFinitePositive(axis, `${path}[${index}]`));
}

function collisionKey(value) {
  return value.normalize("NFC").toLowerCase();
}

function assertNoCollisions(values, path) {
  const seen = new Set();
  for (const [index, value] of values.entries()) {
    const key = collisionKey(value);
    if (seen.has(key)) {
      fail(`${path}[${index}]`);
    }
    seen.add(key);
  }
}

function assertSource(value, path) {
  assertExactFields(value, SOURCE_FIELDS, path);
  if (typeof value.fileId !== "string" || !DRIVE_FILE_ID.test(value.fileId)) {
    fail(fieldPath(path, "fileId"));
  }
  assertFilename(value.filename, fieldPath(path, "filename"), ".blend");
  assertSafePositiveInteger(value.sizeBytes, fieldPath(path, "sizeBytes"));
  assertDigest(value.sha256, fieldPath(path, "sha256"));
}

function assertAtlas(value, path) {
  assertExactFields(value, ATLAS_FIELDS, path);
  assertSafeString(value.id, fieldPath(path, "id"));
  if (value.pack !== "ultimate-buildings") {
    fail(fieldPath(path, "pack"));
  }
  if (typeof value.fileId !== "string" || !DRIVE_FILE_ID.test(value.fileId)) {
    fail(fieldPath(path, "fileId"));
  }
  assertFilename(value.filename, fieldPath(path, "filename"), ".png");
  assertSafePositiveInteger(value.sizeBytes, fieldPath(path, "sizeBytes"));
  assertDigest(value.sha256, fieldPath(path, "sha256"));
  assertFilename(value.stagingBasename, fieldPath(path, "stagingBasename"), ".png");
}

function expectedGodotXyz(raw, scale) {
  return [raw[0] * scale, raw[2] * scale, raw[1] * scale]
    .map((axis) => Math.round(axis * 100000) / 100000);
}

function assertOptionalDigest(value, path) {
  if (value !== null) {
    assertDigest(value, path);
  }
}

function assertOptionalVector(value, path) {
  if (value !== null) {
    assertVector(value, path);
  }
}

function assertModel(value, path, manifestState, atlas) {
  assertExactFields(value, MODEL_FIELDS, path);
  assertSafeString(value.id, fieldPath(path, "id"));
  if (value.category !== "tank" && value.category !== "building") {
    fail(fieldPath(path, "category"));
  }
  if (value.pack !== "animated-tanks" && value.pack !== "ultimate-buildings") {
    fail(fieldPath(path, "pack"));
  }
  assertSource(value.source, fieldPath(path, "source"));
  assertFinitePositive(value.scale, fieldPath(path, "scale"));
  assertVector(value.rawSourceXyz, fieldPath(path, "rawSourceXyz"));
  assertVector(value.expectedGodotXyz, fieldPath(path, "expectedGodotXyz"));
  assertSafeString(value.animationPolicy, fieldPath(path, "animationPolicy"));
  assertSafeString(value.texturePolicy, fieldPath(path, "texturePolicy"));
  assertSafeNonNegativeInteger(value.expectedImageCount, fieldPath(path, "expectedImageCount"));
  if (value.expectedImageCount !== 0 && value.expectedImageCount !== 1) {
    fail(fieldPath(path, "expectedImageCount"));
  }
  assertOptionalDigest(value.outputDigest, fieldPath(path, "outputDigest"));
  assertOptionalVector(value.measuredGodotXyz, fieldPath(path, "measuredGodotXyz"));
  assertOptionalDigest(value.embeddedImageDigest, fieldPath(path, "embeddedImageDigest"));

  const expected = expectedGodotXyz(value.rawSourceXyz, value.scale);
  value.expectedGodotXyz.forEach((axis, index) => {
    if (!Object.is(axis, expected[index])) {
      fail(`${path}.expectedGodotXyz[${index}]`);
    }
  });

  if (value.category === "tank") {
    if (
      value.id !== "tank2" || value.pack !== "animated-tanks" || value.scale !== 0.45 ||
      value.animationPolicy !== "retain_names_for_future_validation" ||
      value.texturePolicy !== "material_color_only" || value.sourceImagePath !== null ||
      value.expectedImageCount !== 0 || value.embeddedImageDigest !== null
    ) {
      fail(path);
    }
  } else if (
    value.pack !== "ultimate-buildings" || value.scale !== 3.6 ||
    value.animationPolicy !== "no_source_clips" || value.texturePolicy !== "embed_selected_atlas" ||
    value.sourceImagePath !== `//${atlas.stagingBasename}` || value.expectedImageCount !== 1
  ) {
    fail(path);
  }

  if (manifestState === "absent") {
    if (value.outputDigest !== null || value.measuredGodotXyz !== null || value.embeddedImageDigest !== null) {
      fail(path);
    }
  } else {
    if (value.outputDigest === null || value.measuredGodotXyz === null || (value.category === "building" && value.embeddedImageDigest === null)) {
      fail(path);
    }
    if (value.measuredGodotXyz !== null) {
      value.measuredGodotXyz.forEach((axis, index) => {
        const tolerance = Math.max(0.01, 0.005 * Math.abs(value.expectedGodotXyz[index]));
        if (Math.abs(axis - value.expectedGodotXyz[index]) > tolerance) {
          fail(`${path}.measuredGodotXyz[${index}]`);
        }
      });
    }
  }
}

function assertCoordinateContract(value) {
  assertExactFields(value, COORDINATE_CONTRACT_FIELDS, "coordinateContract");
  if (value.source !== "blender_xyz") fail("coordinateContract.source");
  if (value.target !== "godot_xyz") fail("coordinateContract.target");
  if (value.expectedGodotXyzFormula !== "round([rawX * scale, rawZ * scale, rawY * scale], 5)") fail("coordinateContract.expectedGodotXyzFormula");
  assertExactFields(value.axisTolerance, AXIS_TOLERANCE_FIELDS, "coordinateContract.axisTolerance");
  if (value.axisTolerance.minimumMeters !== 0.01) fail("coordinateContract.axisTolerance.minimumMeters");
  if (value.axisTolerance.relative !== 0.005) fail("coordinateContract.axisTolerance.relative");
}

function assertConversionManifest(value) {
  assertExactFields(value, CONVERSION_MANIFEST_FIELDS, "conversionManifest");
  if (value.state !== "absent" && value.state !== "present") fail("conversionManifest.state");
  if (!Array.isArray(value.requiredModelFieldsWhenPresent) || value.requiredModelFieldsWhenPresent.length !== REQUIRED_MODEL_FIELDS_WHEN_PRESENT.length) {
    fail("conversionManifest.requiredModelFieldsWhenPresent");
  }
  value.requiredModelFieldsWhenPresent.forEach((field, index) => {
    if (field !== REQUIRED_MODEL_FIELDS_WHEN_PRESENT[index]) fail(`conversionManifest.requiredModelFieldsWhenPresent[${index}]`);
  });
  assertExactFields(value.requirementsWhenPresent, REQUIREMENTS_WHEN_PRESENT_FIELDS, "conversionManifest.requirementsWhenPresent");
  for (const field of REQUIREMENTS_WHEN_PRESENT_FIELDS) {
    if (value.requirementsWhenPresent[field] !== REQUIREMENTS_WHEN_PRESENT[field]) {
      fail(`conversionManifest.requirementsWhenPresent.${field}`);
    }
  }
}

/** Validate a parsed asset lock without reading files or touching process state. */
export function validateAssetLockValue(value) {
  assertExactFields(value, ROOT_FIELDS, "");
  if (value.schemaVersion !== 1) fail("schemaVersion");
  assertCoordinateContract(value.coordinateContract);
  assertConversionManifest(value.conversionManifest);
  if (!Array.isArray(value.models) || value.models.length !== 9) fail("models");
  if (!Array.isArray(value.atlases) || value.atlases.length !== 1) fail("atlases");
  assertAtlas(value.atlases[0], "atlases[0]");
  if (value.atlases[0].stagingBasename !== "Texture.png") fail("atlases[0].stagingBasename");

  value.models.forEach((model, index) => assertModel(model, `models[${index}]`, value.conversionManifest.state, value.atlases[0]));
  const tanks = value.models.filter((model) => model.category === "tank");
  const buildings = value.models.filter((model) => model.category === "building");
  if (tanks.length !== 1 || buildings.length !== 8) fail("models");
  assertNoCollisions(value.models.map((model) => model.id), "models");
  assertNoCollisions(value.models.map((model) => model.source.filename), "models");
  assertNoCollisions(value.atlases.map((atlas) => atlas.id), "atlases");
  assertNoCollisions(value.atlases.map((atlas) => atlas.filename), "atlases");
  assertNoCollisions(value.atlases.map((atlas) => atlas.stagingBasename), "atlases");
  return value;
}

/** Validate JSON text without reading files or touching process state. */
export function validateAssetLockText(text) {
  if (typeof text !== "string" || text.length === 0 || text.charCodeAt(0) === 0xFEFF) {
    fail("text");
  }
  let value;
  try {
    value = JSON.parse(text);
  } catch {
    fail("text");
  }
  return validateAssetLockValue(value);
}

export class AssetLockLoadError extends Error {
  constructor(code, path) {
    super(`Asset lock load failed: ${code}`);
    this.name = "AssetLockLoadError";
    this.code = code;
    this.path = path;
  }
}

export async function loadAndValidateAssetLock(lockPath) {
  let text;
  try {
    text = await readFile(lockPath, "utf8");
  } catch {
    throw new AssetLockLoadError("io_error", "lock");
  }
  try {
    return validateAssetLockText(text);
  } catch (error) {
    if (error instanceof Error) {
      throw new AssetLockLoadError(error.message === "text" ? "parse_error" : "validation_error", error.message);
    }
    throw error;
  }
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
    const lock = await loadAndValidateAssetLock(lockPath);
    writeJsonLine(stdout, { ok: true, schemaVersion: lock.schemaVersion, models: lock.models.length, atlases: lock.atlases.length });
    return 0;
  } catch (error) {
    if (error instanceof AssetLockLoadError) {
      writeJsonLine(stderr, { ok: false, code: error.code, path: error.path });
    } else {
      writeJsonLine(stderr, { ok: false, code: "unexpected_error", path: "internal" });
    }
    return 1;
  }
}

const scriptPath = fileURLToPath(import.meta.url);
if (process.argv[1] !== undefined && resolve(process.argv[1]) === scriptPath) {
  const lockPath = fileURLToPath(new URL("../docs/assets/quaternius-lock.json", import.meta.url));
  process.exitCode = await runAssetLockCli(process.argv.slice(2), { lockPath, stdout: process.stdout, stderr: process.stderr });
}
