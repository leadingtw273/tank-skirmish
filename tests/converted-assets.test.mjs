import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { chmod, mkdtemp, rm, unlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
  CONVERTED_ASSET_ERROR_CODES, ConvertedAssetError, canonicalBytes, checkConvertedAssets, inspectConvertedAssets,
  computeRunIdentity, parseCliArgs, parseGlb, runCli,
} from "../scripts/validate-converted-assets.mjs";

const ids = ["tank2", "1story", "1story-gable-roof", "2story", "2story-slim", "2story-wide", "3story-small", "4story", "6story-stack"];
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

test("closed CLI accepts only the documented modes and absolute argument values", () => {
  assert.deepEqual(parseCliArgs(["--help"]), { mode: "help" });
  assert.equal(parseCliArgs(["--inspect", "--input-root", "/tmp/root", "--runner-manifest", "/tmp/run", "--output-report", "/tmp/report"]).mode, "inspect");
  assert.equal(parseCliArgs(["--check", "--input-root", "/tmp/root", "--manifest", "/tmp/report", "--lock", "/tmp/lock"]).mode, "check");
  for (const args of [[], ["--help", "--check"], ["--inspect", "--input-root", "/tmp/root", "--input-root", "/tmp/two", "--runner-manifest", "/tmp/run", "--output-report", "/tmp/r"], ["--check", "--input-root", "/tmp/root", "--manifest", "/tmp/report", "--lock", "/tmp/lock", "--unknown"]]) expectCode(() => parseCliArgs(args), "USAGE");
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

test("check joins runner, static report, final manifest and present lock by model id", async (t) => {
  const value = await fixture(t);
  const report = inspectConvertedAssets({ inputRoot: value.root, runnerManifest: value.path });
  const metadata = await mkdtemp(join(tmpdir(), "converted-assets-metadata-")); t.after(() => rm(metadata, { recursive: true, force: true }));
  const manifest = join(metadata, "final.json"); writeFileSync(manifest, canonicalBytes(report));
  const source = JSON.parse(readFileSync(new URL("../docs/assets/quaternius-lock.json", import.meta.url), "utf8"));
  source.conversionManifest.state = "present";
  for (const model of source.models) {
    const measured = report.models.find((item) => item.id === model.id);
    model.outputDigest = measured.outputDigest; model.embeddedImageDigest = measured.embeddedImageDigest; model.measuredGodotXyz = [...model.expectedGodotXyz];
  }
  const lock = join(metadata, "lock.json"); await writeFile(lock, JSON.stringify(source));
  assert.equal(checkConvertedAssets({ inputRoot: value.root, manifest, lock }).models.length, 9);
  const mismatch = structuredClone(report); mismatch.models[1].outputDigest = report.models[0].outputDigest; writeFileSync(manifest, canonicalBytes(mismatch));
  expectCode(() => checkConvertedAssets({ inputRoot: value.root, manifest, lock }), "DUPLICATE_DIGEST");
  const joinMismatch = structuredClone(report); joinMismatch.runIdentity = "0".repeat(64); writeFileSync(manifest, canonicalBytes(joinMismatch));
  expectCode(() => checkConvertedAssets({ inputRoot: value.root, manifest, lock }), "JOIN_MISMATCH");
  const invalidLock = structuredClone(source); invalidLock.conversionManifest.state = "absent";
  for (const model of invalidLock.models) {
    model.outputDigest = null; model.embeddedImageDigest = null; model.measuredGodotXyz = null;
  }
  writeFileSync(manifest, canonicalBytes(report)); await writeFile(lock, JSON.stringify(invalidLock));
  expectCode(() => checkConvertedAssets({ inputRoot: value.root, manifest, lock }), "LOCK_INVALID");
});

test("error surface remains closed and does not include private paths", async (t) => {
  const value = await fixture(t); const stderr = { value: "", write(text) { this.value += text; } };
  const result = await runCli(["--inspect", "--input-root", value.root, "--runner-manifest", value.path, "--output-report", join(value.root, "missing", "report.json")], { stdout: { write() {} }, stderr });
  assert.equal(result, 1); assert.equal(stderr.value, "OUTPUT_INVALID\n"); assert.equal(stderr.value.includes(value.root), false);
  assert.equal(CONVERTED_ASSET_ERROR_CODES.has(new ConvertedAssetError("not-closed").code), true);
});
