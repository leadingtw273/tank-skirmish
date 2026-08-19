import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { chmod, mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

import { canonicalBytes, canonicalJson, computeRunIdentity, logicalOutputPath, parseCliArgs, resolveBlenderExecutable, runCli, runConversion, verifyBlenderExecutable } from "../scripts/convert-assets.mjs";

const digest = (bytes) => createHash("sha256").update(bytes).digest("hex");
const closed = ["tank2", "1story", "1story-gable-roof", "2story", "2story-slim", "2story-wide", "3story-small", "4story", "6story-stack"];

test("CLI modes are mutually exclusive and closed mapping rejects hostile ids", () => {
  assert.deepEqual(parseCliArgs(["--help"]), { mode: "help" });
  assert.deepEqual(parseCliArgs(["--check"]), { mode: "check" });
  assert.deepEqual(parseCliArgs(["--output-root", "/tmp/out", "--all"]), { mode: "run", outputRoot: "/tmp/out", all: true });
  for (const bad of [["--help", "--check"], ["--output-root", "/tmp/out", "--item"], ["--output-root", "/tmp/out", "--item", "tank2", "--all"]]) assert.throws(() => parseCliArgs(bad), { message: "USAGE" });
  for (const id of ["Tank2", "tank2/", ".", "..", "unknown"]) assert.throws(() => logicalOutputPath({ id, category: "tank" }), { message: "MODEL_ID_INVALID" });
  assert.equal(logicalOutputPath({ id: "tank2", category: "tank" }), "assets/models/tank/tank2.glb");
});

test("check stays offline and canonical bytes plus run identity are stable", async () => {
  let output = ""; const status = await runCli(["--help"], { stdout: { write: (value) => { output += value; } }, stderr: { write() {} } });
  assert.equal(status, 0); assert.match(output, /--check/);
  assert.equal(canonicalJson({ z: 1, a: [true, null] }), '{"a":[true,null],"z":1}');
  assert.equal(canonicalBytes({ a: 1 }).toString(), '{"a":1}\n');
  const records = [{ id: "tank2", sourceDigest: "a", scale: 0.45, policy: { animation: "retain", texture: "color" }, sourceActionNames: ["Idle"], outputLogicalPath: "assets/models/tank/tank2.glb" }];
  assert.equal(computeRunIdentity({ assetLockDigest: "a", toolchainLockDigest: "b", exporterDigest: "c", models: records }), computeRunIdentity({ assetLockDigest: "a", toolchainLockDigest: "b", exporterDigest: "c", models: records }));
});

test("explicit Blender path is exclusive and Blender identity failures are closed", async (t) => {
  const root = await mkdtemp(join(tmpdir(), "blender-contract-")); t.after(() => rm(root, { recursive: true, force: true }));
  const executable = join(root, "blender"); const bytes = Buffer.from("synthetic blender"); await writeFile(executable, bytes, { mode: 0o700 });
  const tool = { id: "blender", install: { cacheRelativePath: "cache", executableRelativePath: "blender", executableChecksum: { value: digest(bytes) }, versionContract: { firstLine: "Blender 4.5.12 LTS", buildHash: "84afd5f785f7" } } };
  const lock = { tools: [tool] };
  assert.equal(resolveBlenderExecutable(lock, { BLENDER_BIN: executable, TANK_SKIRMISH_TOOL_CACHE: "/definitely-not-used" }), executable);
  assert.throws(() => resolveBlenderExecutable(lock, { BLENDER_BIN: join(root, "missing"), TANK_SKIRMISH_TOOL_CACHE: root }), { message: "BLENDER_INVALID" });
  const version = () => ({ status: 0, stdout: "Blender 4.5.12 LTS\nbuild hash: 84afd5f785f7\n" });
  assert.doesNotThrow(() => verifyBlenderExecutable(executable, tool, version));
  assert.throws(() => verifyBlenderExecutable(executable, { ...tool, install: { ...tool.install, executableChecksum: { value: "0".repeat(64) } } }, version), { message: "BLENDER_DIGEST_MISMATCH" });
  assert.throws(() => verifyBlenderExecutable(executable, tool, () => ({ status: 0, stdout: "Blender 4.5.12 LTS\nwrong\n" })), { message: "BLENDER_VERSION_MISMATCH" });
});

test("offline fake Blender publishes an atomic manifest without private paths", async (t) => {
  const root = await mkdtemp(join(tmpdir(), "conversion-test-")); t.after(() => rm(root, { recursive: true, force: true }));
  const outputRoot = join(root, "output"); await mkdir(outputRoot, { mode: 0o700 }); await chmod(outputRoot, 0o700);
  const fakeBlender = join(root, "blender"); const blenderBytes = Buffer.from("fake blender"); await writeFile(fakeBlender, blenderBytes, { mode: 0o700 });
  const model = { id: "tank2", category: "tank", pack: "animated-tanks", scale: 0.45, animationPolicy: "retain_names_for_future_validation", texturePolicy: "material_color_only", source: { fileId: "file", sha256: "a".repeat(64) } };
  const assetLock = { models: [model] };
  const toolchainLock = { tools: [{ id: "blender", version: "4.5.12", install: { executableChecksum: { value: digest(blenderBytes) }, versionContract: { firstLine: "Blender 4.5.12 LTS", buildHash: "84afd5f785f7" }, cacheRelativePath: "ignored", executableRelativePath: "ignored" } }] };
  async function stageItem() {
    const directory = await mkdtemp(join(outputRoot, "asset-stage-")); await chmod(directory, 0o700);
    const source = join(directory, "Tank2.blend"); await writeFile(source, "blend", { mode: 0o600 });
    return { scale: model.scale, source: { basename: "Tank2.blend", path: source }, atlas: null, async release() { await rm(directory, { recursive: true, force: true }); } };
  }
  const result = await runConversion({ assetLock, toolchainLock, assetLockDigest: "d".repeat(64), toolchainLockDigest: "e".repeat(64), outputRoot, itemIds: ["tank2"], stageItem, blenderPath: fakeBlender, exporterPath: new URL("../scripts/blender/export_selected_glb.py", import.meta.url).pathname, runProcess(executable, args) {
    if (args[0] === "--version") return { status: 0, stdout: "Blender 4.5.12 LTS\nbuild hash: 84afd5f785f7\n" };
    assert.deepEqual(args.slice(0, 6), ["--background", "--factory-startup", "--python", new URL("../scripts/blender/export_selected_glb.py", import.meta.url).pathname, "--", args[5]]);
    const request = JSON.parse(readFileSync(args[5], "utf8"));
    assert.equal(JSON.stringify(request).includes("cache"), false);
    writeFileSync(request.outputPrivatePath, "glb");
    writeFileSync(request.resultPrivatePath, '{"sourceActionNames":["Idle"]}\n');
    return { status: 0, stdout: "" };
  } });
  const manifest = JSON.parse(await readFile(join(outputRoot, "conversion-run-manifest.json"), "utf8"));
  assert.equal(manifest.runIdentity, result.manifest.runIdentity); assert.equal(result.manifestDigest, digest(canonicalBytes(manifest)));
  assert.equal(manifest.models[0].output.logicalPath, "assets/models/tank/tank2.glb"); assert.equal(JSON.stringify(manifest).includes(root), false);
});

test("exporter compiles outside the repository and keeps source contracts", async (t) => {
  const root = await mkdtemp(join(tmpdir(), "exporter-pyc-")); t.after(() => rm(root, { recursive: true, force: true }));
  await chmod(root, 0o700); const source = new URL("../scripts/blender/export_selected_glb.py", import.meta.url).pathname; const cfile = join(root, "exporter.pyc");
  const compiled = spawnSync("python3", ["-c", "import py_compile,sys; py_compile.compile(sys.argv[1], cfile=sys.argv[2], doraise=True)", source, cfile], { encoding: "utf8" });
  assert.equal(compiled.status, 0, compiled.stderr); assert.match(await readFile(source, "utf8"), /BUILDING_IMAGE_PATH = "\/\/Texture\.png"/); assert.match(await readFile(source, "utf8"), /export_draco_mesh_compression_enable/);
});
