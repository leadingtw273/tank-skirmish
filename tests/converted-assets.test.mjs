import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { chmod, mkdtemp, rm, unlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

import {
  CONVERTED_ASSET_ERROR_CODES, ConvertedAssetError, canonicalBytes, checkConvertedAssets, composeConvertedAssets, inspectConvertedAssets,
  computeRunIdentity, parseCliArgs, parseGlb, runCli,
} from "../scripts/validate-converted-assets.mjs";

const ids = ["tank2", "1story", "1story-gable-roof", "2story", "2story-slim", "2story-wide", "3story-small", "4story", "6story-stack"];
const projectRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const sha = (value) => createHash("sha256").update(value).digest("hex");
const logicalPath = (id) => id === "tank2" ? `assets/models/tank/${id}.glb` : `assets/models/buildings/${id}.glb`;

function glb(json, bin = Buffer.alloc(0)) {
  const source = Buffer.from(JSON.stringify(json), "utf8");
  const jsonPadding = (4 - source.length % 4) % 4;
  const jsonBytes = Buffer.concat([source, Buffer.alloc(jsonPadding, 0x20)]);
  const binPadding = (4 - bin.length % 4) % 4;
  const binBytes = Buffer.concat([bin, Buffer.alloc(binPadding)]);
  const bytes = Buffer.alloc(12 + 8 + jsonBytes.length + 8 + binBytes.length);
  bytes.writeUInt32LE(0x46546c67, 0); bytes.writeUInt32LE(2, 4); bytes.writeUInt32LE(bytes.length, 8);
  bytes.writeUInt32LE(jsonBytes.length, 12); bytes.writeUInt32LE(0x4e4f534a, 16); jsonBytes.copy(bytes, 20);
  const position = 20 + jsonBytes.length;
  bytes.writeUInt32LE(binBytes.length, position); bytes.writeUInt32LE(0x004e4942, position + 4); binBytes.copy(bytes, position + 8);
  return bytes;
}
function modelGlb(id, { actions = ["Drive"], image } = {}) {
  const building = id !== "tank2";
  const imageBytes = image ?? Buffer.from(id, "utf8");
  return glb({
    asset: { version: "2.0" }, buffers: [{ byteLength: building ? imageBytes.length : 0 }],
    ...(building ? { bufferViews: [{ buffer: 0, byteOffset: 0, byteLength: imageBytes.length }], images: [{ bufferView: 0, mimeType: "image/png" }] } : {}),
    ...(building ? {} : { animations: actions.map((name) => ({ name })) }),
  }, building ? imageBytes : Buffer.alloc(0));
}
function runner(root, files, { action = ["Drive"] } = {}) {
  const assetBytes = readFileSync(new URL("../docs/assets/quaternius-lock.json", import.meta.url));
  const toolchainBytes = readFileSync(new URL("../docs/toolchain-lock.json", import.meta.url));
  const exporterBytes = readFileSync(new URL("../scripts/blender/export_selected_glb.py", import.meta.url));
  const assetLock = JSON.parse(assetBytes); const toolchain = JSON.parse(toolchainBytes);
  const blenderTool = toolchain.tools.find((tool) => tool.id === "blender");
  const blender = { executableChecksum: blenderTool.install.executableChecksum.value, id: blenderTool.id, version: blenderTool.version, versionContract: blenderTool.install.versionContract };
  const exporterSourceDigest = sha(exporterBytes);
  const value = {
    blender, exporterSourceDigest, models: ids.map((id) => {
      const locked = assetLock.models.find((model) => model.id === id);
      return {
        blender, category: id === "tank2" ? "tank" : "building", exporterSourceDigest, id,
        output: { digest: sha(files.get(id)), logicalPath: logicalPath(id) }, policy: { animation: locked.animationPolicy, texture: locked.texturePolicy },
        scale: locked.scale, source: { digest: locked.source.sha256, fileId: locked.source.fileId }, sourceActionNames: id === "tank2" ? action : [],
      };
    }), runIdentity: "", schemaVersion: 1,
  };
  value.runIdentity = computeRunIdentity({ assetLockDigest: sha(assetBytes), toolchainLockDigest: sha(toolchainBytes), exporterDigest: exporterSourceDigest, models: value.models.map((model) => ({ id: model.id, outputLogicalPath: model.output.logicalPath, policy: model.policy, scale: model.scale, sourceActionNames: model.sourceActionNames, sourceDigest: model.source.digest })) });
  const path = join(root, "conversion-run-manifest.json"); writeFileSync(path, canonicalBytes(value)); return { path, value };
}
async function fixture(t, options = {}) {
  const root = await mkdtemp(join(tmpdir(), "converted-assets-")); await chmod(root, 0o700);
  t.after(() => rm(root, { recursive: true, force: true }));
  mkdirSync(join(root, "assets", "models", "tank"), { recursive: true }); mkdirSync(join(root, "assets", "models", "buildings"), { recursive: true });
  const files = new Map();
  for (const id of ids) {
    const bytes = modelGlb(id, options.glbs?.[id]); files.set(id, bytes);
    writeFileSync(join(root, ...logicalPath(id).split("/")), bytes);
  }
  const run = runner(root, files, options.runner);
  return { root, files, ...run };
}
function expectCode(action, code) { assert.throws(action, (error) => error instanceof ConvertedAssetError && error.code === code); }
async function compositeFixture(t, { present = false } = {}) {
  const value = await fixture(t);
  const metadata = await mkdtemp(join(tmpdir(), "converted-assets-metadata-")); t.after(() => rm(metadata, { recursive: true, force: true }));
  const staticReport = inspectConvertedAssets({ inputRoot: value.root, runnerManifest: value.path });
  const staticPath = join(metadata, "static.json"); writeFileSync(staticPath, canonicalBytes(staticReport));
  const measurement = { schemaVersion: 1, staticReportDigest: sha(canonicalBytes(staticReport)), models: staticReport.models.map((model) => ({ id: model.id, outputDigest: model.outputDigest, measuredGodotXyz: [...lockValueForId(idToLock(), model.id).expectedGodotXyz] })) };
  const measurementPath = join(metadata, "measurement.json"); writeFileSync(measurementPath, canonicalBytes(measurement));
  const lockValue = idToLock();
  if (present) {
    lockValue.conversionManifest.state = "present";
    for (const model of lockValue.models) {
      const actual = staticReport.models.find((candidate) => candidate.id === model.id);
      model.outputDigest = actual.outputDigest; model.embeddedImageDigest = actual.embeddedImageDigest; model.measuredGodotXyz = [...model.expectedGodotXyz];
    }
  }
  const lock = join(metadata, "lock.json"); writeFileSync(lock, JSON.stringify(lockValue));
  const output = join(metadata, "composite.json");
  return { ...value, metadata, staticReport, staticPath, measurement, measurementPath, lock, lockValue, output };
}
function idToLock() { return JSON.parse(readFileSync(new URL("../docs/assets/quaternius-lock.json", import.meta.url), "utf8")); }
function lockValueForId(lockValue, id) { return lockValue.models.find((model) => model.id === id); }
function expectedCompositeFromInputs(value) {
  const runnerById = new Map(value.value.models.map((model) => [model.id, model]));
  const staticById = new Map(value.staticReport.models.map((model) => [model.id, model]));
  const measurementById = new Map(value.measurement.models.map((model) => [model.id, model]));
  return {
    schemaVersion: 1,
    runnerManifestDigest: value.staticReport.runnerManifestDigest,
    runnerRunIdentity: value.staticReport.runIdentity,
    toolchain: value.staticReport.toolchain,
    exporterDigest: value.staticReport.exporter.sourceDigest,
    models: ids.map((id) => {
      const runnerModel = runnerById.get(id); const staticModel = staticById.get(id); const measurementModel = measurementById.get(id);
      return {
        id, category: runnerModel.category, sourceFileId: runnerModel.source.fileId, sourceDigest: runnerModel.source.digest,
        scale: runnerModel.scale, sourceActionNames: [...runnerModel.sourceActionNames].sort(), outputRelativePath: staticModel.outputRelativePath,
        outputDigest: staticModel.outputDigest, animationNames: [...staticModel.animationNames].sort(), imageCount: staticModel.imageCount,
        embeddedImageDigest: staticModel.embeddedImageDigest, measuredGodotXyz: measurementModel.measuredGodotXyz,
      };
    }),
  };
}

test("closed CLI accepts only the documented modes and absolute argument values", () => {
  assert.deepEqual(parseCliArgs(["--help"]), { mode: "help" });
  assert.equal(parseCliArgs(["--inspect", "--input-root", "/tmp/root", "--runner-manifest", "/tmp/run", "--output-report", "/tmp/report"]).mode, "inspect");
  assert.equal(parseCliArgs(["--compose", "--input-root", "/tmp/root", "--runner-manifest", "/tmp/run", "--static-report", "/tmp/static", "--measurement-report", "/tmp/measurement", "--lock", "/tmp/lock", "--output-manifest", "/tmp/output"]).mode, "compose");
  assert.equal(parseCliArgs(["--check", "--input-root", "/tmp/root", "--manifest", "/tmp/report", "--lock", "/tmp/lock"]).mode, "check");
  for (const args of [[], ["--help", "--check"], ["--inspect", "--input-root", "/tmp/root", "--input-root", "/tmp/two", "--runner-manifest", "/tmp/run", "--output-report", "/tmp/r"], ["--compose", "--input-root", "/tmp/root", "--runner-manifest", "/tmp/run", "--static-report", "/tmp/static", "--measurement-report", "/tmp/measurement", "--lock", "/tmp/lock", "--output-manifest", "/tmp/output", "--lock", "/tmp/two"], ["--check", "--input-root", "/tmp/root", "--manifest", "/tmp/report", "--lock", "/tmp/lock", "--unknown"]]) expectCode(() => parseCliArgs(args), "USAGE");
  expectCode(() => parseCliArgs(["--inspect", "--input-root", "relative", "--runner-manifest", "/tmp/run", "--output-report", "/tmp/r"]), "PATH_INVALID");
});

test("parser accepts the supported GLB shape and rejects header, chunk, JSON, bufferView, accessor, URI, and image violations", () => {
  const valid = modelGlb("1story");
  assert.equal(parseGlb(valid).imageCount, 1);
  const header = Buffer.from(valid); header.writeUInt32LE(0, 0); expectCode(() => parseGlb(header), "GLB_HEADER_INVALID");
  const length = Buffer.from(valid); length.writeUInt32LE(length.length - 1, 8); expectCode(() => parseGlb(length), "GLB_HEADER_INVALID");
  expectCode(() => parseGlb(valid.subarray(0, valid.length - 1)), "GLB_HEADER_INVALID");
  const chunk = Buffer.from(valid); chunk.writeUInt32LE(3, 12); expectCode(() => parseGlb(chunk), "GLB_CHUNK_INVALID");
  const malformedJson = Buffer.from(valid); malformedJson[20] = 0x21; expectCode(() => parseGlb(malformedJson), "GLB_JSON_INVALID");
  expectCode(() => parseGlb(glb({ buffers: [{ byteLength: 4, uri: "data:bad" }] }, Buffer.from([1, 2, 3, 4]))), "GLB_STRUCTURE_INVALID");
  expectCode(() => parseGlb(glb({ buffers: [{ byteLength: 4 }], bufferViews: [{ buffer: 0, byteOffset: 3, byteLength: 2 }] }, Buffer.from([1, 2, 3, 4]))), "GLB_STRUCTURE_INVALID");
  expectCode(() => parseGlb(glb({ buffers: [{ byteLength: 4 }], bufferViews: [{ buffer: 0, byteOffset: 0, byteLength: 4 }], accessors: [{ bufferView: 0, componentType: 5126, type: "VEC3", count: 1 }] }, Buffer.from([1, 2, 3, 4]))), "GLB_STRUCTURE_INVALID");
  expectCode(() => parseGlb(glb({ buffers: [{ byteLength: 4 }], bufferViews: [{ buffer: 0, byteOffset: Number.MAX_SAFE_INTEGER, byteLength: 1 }] }, Buffer.from([1, 2, 3, 4]))), "GLB_STRUCTURE_INVALID");
  expectCode(() => parseGlb(glb({ buffers: [{ byteLength: 4 }], bufferViews: [{ buffer: 0, byteOffset: 0, byteLength: 4 }], accessors: [{ bufferView: 0, byteOffset: Number.MAX_SAFE_INTEGER, componentType: 5121, type: "SCALAR", count: 1 }] }, Buffer.from([1, 2, 3, 4]))), "GLB_STRUCTURE_INVALID");
  expectCode(() => parseGlb(glb({ buffers: [{ byteLength: 4 }], bufferViews: [{ buffer: 0, byteOffset: 0, byteLength: 4 }], accessors: [{ bufferView: 0, componentType: 5121, type: "SCALAR", count: Number.MAX_SAFE_INTEGER }] }, Buffer.from([1, 2, 3, 4]))), "GLB_STRUCTURE_INVALID");
  expectCode(() => parseGlb(glb({ buffers: [{ byteLength: 4 }], images: [{ uri: "https://example.invalid/a.png" }] }, Buffer.from([1, 2, 3, 4]))), "GLB_STRUCTURE_INVALID");
  expectCode(() => parseGlb(glb({ buffers: [{ byteLength: 4 }], bufferViews: [{ buffer: 0, byteOffset: 0, byteLength: 4 }, { buffer: 0, byteOffset: 1, byteLength: 2 }], images: [{ bufferView: 0, mimeType: "image/png" }, { bufferView: 1, mimeType: "image/png" }] }, Buffer.from([1, 2, 3, 4]))), "GLB_STRUCTURE_INVALID");
});

test("inspection produces a canonical report with sorted action names and exact embedded image bytes", async (t) => {
  const value = await fixture(t, { glbs: { tank2: { actions: ["Zulu", "Alpha"] } }, runner: { action: ["Alpha", "Zulu"] } });
  const report = inspectConvertedAssets({ inputRoot: value.root, runnerManifest: value.path });
  assert.deepEqual(Object.keys(report), ["schemaVersion", "runIdentity", "runnerManifestDigest", "toolchain", "exporter", "models"]);
  assert.deepEqual(report.models.map((model) => model.id), ids);
  assert.deepEqual(report.models[0].animationNames, ["Alpha", "Zulu"]);
  assert.equal(report.models[0].embeddedImageDigest, null);
  assert.equal(report.models[1].embeddedImageDigest, sha(Buffer.from("1story", "utf8")));
  const output = join(value.root, "report.json");
  assert.equal(await runCli(["--inspect", "--input-root", value.root, "--runner-manifest", value.path, "--output-report", output]), 0);
  const bytes = readFileSync(output); assert.deepEqual(bytes, canonicalBytes(JSON.parse(bytes)));
});

test("inspection fail-closes output trees, runner paths and model contracts", async (t) => {
  const badTree = await fixture(t); writeFileSync(join(badTree.root, "unexpected.txt"), "x"); expectCode(() => inspectConvertedAssets({ inputRoot: badTree.root, runnerManifest: badTree.path }), "OUTPUT_INVALID");
  const missingOutput = await fixture(t); await unlink(join(missingOutput.root, ...logicalPath("1story").split("/"))); expectCode(() => inspectConvertedAssets({ inputRoot: missingOutput.root, runnerManifest: missingOutput.path }), "OUTPUT_INVALID");
  const nonCanonical = await fixture(t); writeFileSync(nonCanonical.path, `${JSON.stringify(nonCanonical.value, null, 2)}\n`); expectCode(() => inspectConvertedAssets({ inputRoot: nonCanonical.root, runnerManifest: nonCanonical.path }), "CANONICAL_MANIFEST_INVALID");
  const badId = await fixture(t); badId.value.models[1].id = "1STORY"; writeFileSync(badId.path, canonicalBytes(badId.value)); expectCode(() => inspectConvertedAssets({ inputRoot: badId.root, runnerManifest: badId.path }), "RUNNER_MANIFEST_INVALID");
  const badPath = await fixture(t); badPath.value.models[0].output.logicalPath = "assets/models/tank/../tank2.glb"; writeFileSync(badPath.path, canonicalBytes(badPath.value)); expectCode(() => inspectConvertedAssets({ inputRoot: badPath.root, runnerManifest: badPath.path }), "RUNNER_MANIFEST_INVALID");
  const badAction = await fixture(t, { glbs: { tank2: { actions: ["Other"] } } }); expectCode(() => inspectConvertedAssets({ inputRoot: badAction.root, runnerManifest: badAction.path }), "GLB_STRUCTURE_INVALID");
  const badBuilding = await fixture(t, { glbs: { "1story": { image: Buffer.from([9, 9, 9, 9]) } } }); badBuilding.value.models[1].output.digest = "0".repeat(64); writeFileSync(badBuilding.path, canonicalBytes(badBuilding.value)); expectCode(() => inspectConvertedAssets({ inputRoot: badBuilding.root, runnerManifest: badBuilding.path }), "DIGEST_MISMATCH");
});

test("compose writes independently-derived canonical bytes, accepts absent and matching-present locks, and production check has no private runner dependency", async (t) => {
  const value = await compositeFixture(t);
  const args = ["--compose", "--input-root", value.root, "--runner-manifest", value.path, "--static-report", value.staticPath, "--measurement-report", value.measurementPath, "--lock", value.lock, "--output-manifest", value.output];
  assert.equal(await runCli(args), 0);
  const expected = expectedCompositeFromInputs(value); const bytes = readFileSync(value.output);
  assert.deepEqual(bytes, canonicalBytes(expected));
  assert.equal(bytes.toString("utf8").endsWith("\n\n"), false);
  const composite = JSON.parse(bytes);
  const matchingPresent = await compositeFixture(t, { present: true });
  assert.deepEqual(composeConvertedAssets({ inputRoot: matchingPresent.root, runnerManifest: matchingPresent.path, staticReport: matchingPresent.staticPath, measurementReport: matchingPresent.measurementPath, lock: matchingPresent.lock }), expectedCompositeFromInputs(matchingPresent));
  const present = structuredClone(value.lockValue); present.conversionManifest.state = "present";
  for (const model of present.models) {
    const actual = composite.models.find((candidate) => candidate.id === model.id);
    model.outputDigest = actual.outputDigest; model.embeddedImageDigest = actual.embeddedImageDigest; model.measuredGodotXyz = actual.measuredGodotXyz;
  }
  writeFileSync(value.lock, JSON.stringify(present));
  assert.equal(checkConvertedAssets({ inputRoot: value.root, manifest: value.output, lock: value.lock }).models.length, 9);
  await unlink(value.path);
  assert.equal(checkConvertedAssets({ inputRoot: value.root, manifest: value.output, lock: value.lock }).models.length, 9);
});

test("compose rejects static, measurement, runner and lock drift without exposing private paths", async (t) => {
  const composeArgs = (value) => ({ inputRoot: value.root, runnerManifest: value.path, staticReport: value.staticPath, measurementReport: value.measurementPath, lock: value.lock });
  const staticContent = await compositeFixture(t); const changedStatic = structuredClone(staticContent.staticReport); changedStatic.models[0].outputDigest = "0".repeat(64); writeFileSync(staticContent.staticPath, canonicalBytes(changedStatic));
  expectCode(() => composeConvertedAssets(composeArgs(staticContent)), "JOIN_MISMATCH");
  const staticId = await compositeFixture(t); const invalidStaticId = structuredClone(staticId.staticReport); invalidStaticId.models[0].id = "unknown"; writeFileSync(staticId.staticPath, canonicalBytes(invalidStaticId));
  expectCode(() => composeConvertedAssets(composeArgs(staticId)), "STATIC_MANIFEST_INVALID");
  const staticDuplicate = await compositeFixture(t); const duplicateStatic = structuredClone(staticDuplicate.staticReport); duplicateStatic.models[1].outputDigest = duplicateStatic.models[0].outputDigest; writeFileSync(staticDuplicate.staticPath, canonicalBytes(duplicateStatic));
  expectCode(() => composeConvertedAssets(composeArgs(staticDuplicate)), "DUPLICATE_DIGEST");
  const measurementDigest = await compositeFixture(t); const changedMeasurementDigest = structuredClone(measurementDigest.measurement); changedMeasurementDigest.models[0].outputDigest = "0".repeat(64); writeFileSync(measurementDigest.measurementPath, canonicalBytes(changedMeasurementDigest));
  expectCode(() => composeConvertedAssets(composeArgs(measurementDigest)), "JOIN_MISMATCH");
  const measurementId = await compositeFixture(t); const invalidMeasurementId = structuredClone(measurementId.measurement); invalidMeasurementId.models[0].id = "unknown"; writeFileSync(measurementId.measurementPath, canonicalBytes(invalidMeasurementId));
  expectCode(() => composeConvertedAssets(composeArgs(measurementId)), "MEASUREMENT_REPORT_INVALID");
  const runnerId = await compositeFixture(t); runnerId.value.models[0].id = "unknown"; writeFileSync(runnerId.path, canonicalBytes(runnerId.value));
  expectCode(() => composeConvertedAssets(composeArgs(runnerId)), "RUNNER_MANIFEST_INVALID");
  const lockId = await compositeFixture(t); const invalidLockId = structuredClone(lockId.lockValue); invalidLockId.models[0].id = "unknown"; writeFileSync(lockId.lock, JSON.stringify(invalidLockId));
  expectCode(() => composeConvertedAssets(composeArgs(lockId)), "LOCK_INVALID");
  const lockScale = await compositeFixture(t); const invalidLockScale = structuredClone(lockScale.lockValue); invalidLockScale.models[0].scale = 1; writeFileSync(lockScale.lock, JSON.stringify(invalidLockScale));
  expectCode(() => composeConvertedAssets(composeArgs(lockScale)), "LOCK_INVALID");
  const presentMismatch = await compositeFixture(t, { present: true }); const invalidPresent = structuredClone(presentMismatch.lockValue); invalidPresent.models[0].outputDigest = "0".repeat(64); writeFileSync(presentMismatch.lock, JSON.stringify(invalidPresent));
  expectCode(() => composeConvertedAssets(composeArgs(presentMismatch)), "JOIN_MISMATCH");
  const privatePath = await compositeFixture(t); const privateStatic = structuredClone(privatePath.staticReport); privateStatic.privatePath = privatePath.root; writeFileSync(privatePath.staticPath, canonicalBytes(privateStatic));
  const stderr = { value: "", write(text) { this.value += text; } };
  assert.equal(await runCli(["--compose", "--input-root", privatePath.root, "--runner-manifest", privatePath.path, "--static-report", privatePath.staticPath, "--measurement-report", privatePath.measurementPath, "--lock", privatePath.lock, "--output-manifest", privatePath.output], { stdout: { write() {} }, stderr }), 1);
  assert.equal(stderr.value, "STATIC_MANIFEST_INVALID\n"); assert.equal(stderr.value.includes(privatePath.root), false);
});

test("check rejects legacy static-only and measurement-only manifests, then fails closed for production-tree drift", async (t) => {
  const value = await compositeFixture(t);
  const args = { inputRoot: value.root, runnerManifest: value.path, staticReport: value.staticPath, measurementReport: value.measurementPath, lock: value.lock };
  const badDigest = structuredClone(value.measurement); badDigest.staticReportDigest = "0".repeat(64); writeFileSync(value.measurementPath, canonicalBytes(badDigest));
  expectCode(() => composeConvertedAssets(args), "DIGEST_MISMATCH");
  writeFileSync(value.measurementPath, canonicalBytes(value.measurement));
  const badSource = JSON.parse(readFileSync(value.lock, "utf8")); badSource.models[0].source.sha256 = "0".repeat(64); writeFileSync(value.lock, JSON.stringify(badSource));
  expectCode(() => composeConvertedAssets(args), "JOIN_MISMATCH");
  writeFileSync(value.lock, JSON.stringify(value.lockValue));
  const composite = composeConvertedAssets(args); const manifest = join(value.metadata, "manifest.json"); writeFileSync(manifest, canonicalBytes(composite));
  const present = structuredClone(value.lockValue); present.conversionManifest.state = "present";
  for (const model of present.models) { const actual = composite.models.find((candidate) => candidate.id === model.id); model.outputDigest = actual.outputDigest; model.embeddedImageDigest = actual.embeddedImageDigest; model.measuredGodotXyz = actual.measuredGodotXyz; }
  writeFileSync(value.lock, JSON.stringify(present));
  expectCode(() => checkConvertedAssets({ inputRoot: value.root, manifest: value.staticPath, lock: value.lock }), "FINAL_MANIFEST_INVALID");
  expectCode(() => checkConvertedAssets({ inputRoot: value.root, manifest: value.measurementPath, lock: value.lock }), "FINAL_MANIFEST_INVALID");
  const unknown = structuredClone(composite); unknown.privatePath = value.root; writeFileSync(manifest, canonicalBytes(unknown));
  expectCode(() => checkConvertedAssets({ inputRoot: value.root, manifest, lock: value.lock }), "FINAL_MANIFEST_INVALID");
  writeFileSync(manifest, canonicalBytes(composite));
  writeFileSync(join(value.root, "assets", "models", "buildings", "extra.glb"), modelGlb("1story"));
  expectCode(() => checkConvertedAssets({ inputRoot: value.root, manifest, lock: value.lock }), "OUTPUT_INVALID");
  await unlink(join(value.root, "assets", "models", "buildings", "extra.glb"));
  await unlink(join(value.root, ...logicalPath("1story").split("/")));
  expectCode(() => checkConvertedAssets({ inputRoot: value.root, manifest, lock: value.lock }), "OUTPUT_INVALID");
  writeFileSync(join(value.root, ...logicalPath("1story").split("/")), value.files.get("1story"));
  const staticDrift = structuredClone(composite); staticDrift.models[1].embeddedImageDigest = "0".repeat(64); writeFileSync(manifest, canonicalBytes(staticDrift));
  expectCode(() => checkConvertedAssets({ inputRoot: value.root, manifest, lock: value.lock }), "JOIN_MISMATCH");
  const duplicate = structuredClone(composite); duplicate.models[1].outputDigest = duplicate.models[0].outputDigest; writeFileSync(manifest, canonicalBytes(duplicate));
  expectCode(() => checkConvertedAssets({ inputRoot: value.root, manifest, lock: value.lock }), "DUPLICATE_DIGEST");
});

test("compose rejects pre-existing output and never copies lock expected measurements into actuals", async (t) => {
  const value = await compositeFixture(t);
  const output = value.output; writeFileSync(output, "old");
  const stderr = { value: "", write(text) { this.value += text; } };
  const result = await runCli(["--compose", "--input-root", value.root, "--runner-manifest", value.path, "--static-report", value.staticPath, "--measurement-report", value.measurementPath, "--lock", value.lock, "--output-manifest", output], { stdout: { write() {} }, stderr });
  assert.equal(result, 1); assert.equal(stderr.value, "OUTPUT_INVALID\n"); assert.equal(readFileSync(output, "utf8"), "old");
  await unlink(output);
  const composite = composeConvertedAssets({ inputRoot: value.root, runnerManifest: value.path, staticReport: value.staticPath, measurementReport: value.measurementPath, lock: value.lock });
  const changed = structuredClone(value.lockValue); changed.models[0].rawSourceXyz[0] += 0.01; changed.models[0].expectedGodotXyz[0] = Math.round(changed.models[0].rawSourceXyz[0] * changed.models[0].scale * 100000) / 100000; writeFileSync(value.lock, JSON.stringify(changed));
  assert.deepEqual(composeConvertedAssets({ inputRoot: value.root, runnerManifest: value.path, staticReport: value.staticPath, measurementReport: value.measurementPath, lock: value.lock }).models[0].measuredGodotXyz, composite.models[0].measuredGodotXyz);
});

test("error surface remains closed and does not include private paths", async (t) => {
  const value = await fixture(t); const stderr = { value: "", write(text) { this.value += text; } };
  const result = await runCli(["--inspect", "--input-root", value.root, "--runner-manifest", value.path, "--output-report", join(value.root, "missing", "report.json")], { stdout: { write() {} }, stderr });
  assert.equal(result, 1); assert.equal(stderr.value, "OUTPUT_INVALID\n"); assert.equal(stderr.value.includes(value.root), false);
  assert.equal(CONVERTED_ASSET_ERROR_CODES.has(new ConvertedAssetError("not-closed").code), true);
});

test("production Godot CLI unwraps successful parse payloads and preserves closed failures", async (t) => {
  const godot = process.env.GODOT_BIN;
  if (godot === undefined) {
    t.skip("GODOT_BIN is required for production Godot CLI coverage");
    return;
  }
  const value = await fixture(t);
  const staticReport = join(value.root, "static-report.json");
  const validStaticReport = inspectConvertedAssets({ inputRoot: value.root, runnerManifest: value.path });
  writeFileSync(staticReport, canonicalBytes(validStaticReport));
  const missingInput = join(value.root, "missing-input");
  const emit = spawnSync(godot, ["--headless", "--audio-driver", "Dummy", "--path", ".", "--script", "res://scripts/measure-converted-assets.gd", "--", "--emit", "--input-root", missingInput, "--static-report", staticReport, "--output-report", join(value.root, "report.json")], { cwd: projectRoot, encoding: "utf8", timeout: 10_000, killSignal: "SIGKILL" });
  assert.equal(emit.error, undefined);
  assert.equal(emit.status, 1);
  assert.equal(emit.stderr, "INPUT_ROOT_INVALID\n");
  assert.equal(`${emit.stdout}${emit.stderr}`.includes("SCRIPT ERROR"), false);
  const check = spawnSync(godot, ["--headless", "--audio-driver", "Dummy", "--path", ".", "--script", "res://scripts/measure-converted-assets.gd", "--", "--check", "--input-root", missingInput, "--manifest", join(value.root, "missing-manifest.json"), "--lock", join(value.root, "missing-lock.json")], { cwd: projectRoot, encoding: "utf8", timeout: 10_000, killSignal: "SIGKILL" });
  assert.equal(check.error, undefined);
  assert.equal(check.status, 1);
  assert.equal(check.stderr, "INPUT_ROOT_INVALID\n");
  assert.equal(`${check.stdout}${check.stderr}`.includes("SCRIPT ERROR"), false);
  const usage = spawnSync(godot, ["--headless", "--audio-driver", "Dummy", "--path", ".", "--script", "res://scripts/measure-converted-assets.gd", "--", "--emit"], { cwd: projectRoot, encoding: "utf8", timeout: 10_000, killSignal: "SIGKILL" });
  assert.equal(usage.error, undefined);
  assert.equal(usage.status, 2);
  assert.equal(usage.stderr, "USAGE\n");
  assert.equal(`${usage.stdout}${usage.stderr}`.includes("SCRIPT ERROR"), false);
  for (const imageCount of [-1, 1.5, "1"]) {
    const invalid = structuredClone(validStaticReport);
    invalid.models[0].imageCount = imageCount;
    writeFileSync(staticReport, canonicalBytes(invalid));
    const result = spawnSync(godot, ["--headless", "--audio-driver", "Dummy", "--path", ".", "--script", "res://scripts/measure-converted-assets.gd", "--", "--emit", "--input-root", missingInput, "--static-report", staticReport, "--output-report", join(value.root, "report.json")], { cwd: projectRoot, encoding: "utf8", timeout: 10_000, killSignal: "SIGKILL" });
    assert.equal(result.error, undefined);
    assert.equal(result.status, 1);
    assert.equal(result.stderr, "STATIC_REPORT_INVALID\n");
    assert.equal(`${result.stdout}${result.stderr}`.includes("SCRIPT ERROR"), false);
  }
});
