import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync, statSync, writeFileSync } from "node:fs";
import { chmod, mkdtemp, mkdir, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";

import {
  CONVERSION_ERROR_CODES, ConversionError, canonicalBytes, canonicalJson, computeRunIdentity,
  logicalOutputPath, parseCliArgs, resolveBlenderExecutable, runCli, runConversion, verifyBlenderExecutable,
} from "../scripts/convert-assets.mjs";

const digest = (bytes) => createHash("sha256").update(bytes).digest("hex");
const exporterPath = new URL("../scripts/blender/export_selected_glb.py", import.meta.url).pathname;
const closed = ["tank2", "1story", "1story-gable-roof", "2story", "2story-slim", "2story-wide", "3story-small", "4story", "6story-stack"];
const source = { fileId: "file", sha256: "a".repeat(64), filename: "Tank2.blend" };

function syntheticModel(overrides = {}) {
  return {
    id: "tank2", category: "tank", pack: "animated-tanks", scale: 0.45,
    animationPolicy: "retain_names_for_future_validation", texturePolicy: "material_color_only", source,
    ...overrides,
  };
}

async function createFixture(t, { rootSuffix = "conversion-test" } = {}) {
  const root = await mkdtemp(join(tmpdir(), `${rootSuffix}-`));
  t.after(() => rm(root, { recursive: true, force: true }));
  await chmod(root, 0o700);
  const outputRoot = join(root, "output-home-cache");
  await mkdir(outputRoot, { mode: 0o700 });
  await chmod(outputRoot, 0o700);
  const fakeBlender = join(root, "blender");
  const blenderBytes = Buffer.from("fake blender");
  await writeFile(fakeBlender, blenderBytes, { mode: 0o700 });
  const model = syntheticModel();
  const toolchainLock = {
    tools: [{ id: "blender", version: "4.5.12", install: {
      executableChecksum: { value: digest(blenderBytes) },
      versionContract: { firstLine: "Blender 4.5.12 LTS", buildHash: "84afd5f785f7" },
      cacheRelativePath: "ignored", executableRelativePath: "ignored",
    } }],
  };
  const stageItem = async () => {
    const directory = await mkdtemp(join(outputRoot, "asset-stage-"));
    await chmod(directory, 0o700);
    const sourcePath = join(directory, model.source.filename);
    await writeFile(sourcePath, "blend", { mode: 0o600 });
    return {
      scale: model.scale,
      source: { basename: model.source.filename, path: sourcePath }, atlas: null,
      async release() { await rm(directory, { recursive: true, force: true }); },
    };
  };
  return { root, outputRoot, fakeBlender, model, toolchainLock, stageItem };
}

function versionOrExport(fakeBlender, onExport) {
  return (executable, args) => {
    assert.equal(executable, fakeBlender);
    if (args.length === 1 && args[0] === "--version") return { status: 0, stdout: "Blender 4.5.12 LTS\nbuild hash: 84afd5f785f7\n" };
    return onExport(args);
  };
}

async function runFakeConversion(t, { onExport, fixture: existingFixture } = {}) {
  const fixture = existingFixture ?? await createFixture(t);
  const observed = [];
  const result = await runConversion({
    assetLock: { models: [fixture.model] }, toolchainLock: fixture.toolchainLock,
    assetLockDigest: "d".repeat(64), toolchainLockDigest: "e".repeat(64),
    outputRoot: fixture.outputRoot, itemIds: ["tank2"], stageItem: fixture.stageItem,
    blenderPath: fixture.fakeBlender, exporterPath,
    runProcess: versionOrExport(fixture.fakeBlender, (args) => {
      observed.push(args);
      const request = JSON.parse(readFileSync(args.at(-1), "utf8"));
      if (onExport !== undefined) return onExport({ args, request });
      writeFileSync(request.outputPrivatePath, "deterministic glb");
      writeFileSync(request.resultPrivatePath, '{"sourceActionNames":["Idle"]}\n');
      return { status: 0, stdout: "" };
    }),
  });
  return { ...fixture, observed, result };
}

test("CLI modes are mutually exclusive and closed mapping rejects hostile ids", () => {
  assert.deepEqual(parseCliArgs(["--help"]), { mode: "help" });
  assert.deepEqual(parseCliArgs(["--check"]), { mode: "check" });
  assert.deepEqual(parseCliArgs(["--output-root", "/tmp/out", "--all"]), { mode: "run", outputRoot: "/tmp/out", all: true });
  assert.deepEqual(parseCliArgs(["--output-root", "/tmp/out", "--item", "tank2"]), { mode: "run", outputRoot: "/tmp/out", itemId: "tank2" });
  for (const bad of [["--help", "--check"], ["--output-root", "/tmp/out", "--item"], ["--output-root", "/tmp/out", "--item", "tank2", "--all"], ["--wat"], ["--output-root", "/tmp/out", "--all", "--all"]]) {
    assert.throws(() => parseCliArgs(bad), { message: "USAGE" });
  }
  for (const id of ["Tank2", "tank2/", "tank2\\", ".", "..", "unknown"]) assert.throws(() => logicalOutputPath({ id, category: "tank" }), { message: "MODEL_ID_INVALID" });
  for (const id of closed) assert.match(logicalOutputPath({ id, category: id === "tank2" ? "tank" : "building" }), /^assets\/models\/(tank|buildings)\/.+\.glb$/u);
  assert.equal(logicalOutputPath({ id: "tank2", category: "tank" }), "assets/models/tank/tank2.glb");
  assert.equal(logicalOutputPath({ id: "1story", category: "building" }), "assets/models/buildings/1story.glb");
});

test("help and check remain offline while canonical bytes and identity are deterministic", async () => {
  let stdout = "";
  assert.equal(await runCli(["--help"], { stdout: { write: (value) => { stdout += value; } }, stderr: { write() {} }, environment: { BLENDER_BIN: "/missing" } }), 0);
  assert.match(stdout, /--check/u);
  assert.equal(await runCli(["--check"], { stdout: { write() {} }, stderr: { write() {} }, environment: { BLENDER_BIN: "/missing", TANK_SKIRMISH_ASSET_CACHE: "/missing" } }), 0);
  assert.equal(canonicalJson({ z: 1, a: [true, null] }), '{"a":[true,null],"z":1}');
  assert.equal(canonicalBytes({ a: 1 }).toString(), '{"a":1}\n');
  const records = [{ id: "tank2", sourceDigest: "a", scale: 0.45, policy: { animation: "retain", texture: "color" }, sourceActionNames: ["Idle"], outputLogicalPath: "assets/models/tank/tank2.glb" }];
  const stable = computeRunIdentity({ assetLockDigest: "a", toolchainLockDigest: "b", exporterDigest: "c", models: records });
  assert.equal(stable, computeRunIdentity({ assetLockDigest: "a", toolchainLockDigest: "b", exporterDigest: "c", models: records }));
  assert.notEqual(stable, computeRunIdentity({ assetLockDigest: "changed", toolchainLockDigest: "b", exporterDigest: "c", models: records }));
  assert.notEqual(stable, computeRunIdentity({ assetLockDigest: "a", toolchainLockDigest: "b", exporterDigest: "c", models: [{ ...records[0], scale: 1 }] }));
});

test("explicit Blender path is exclusive and identity failures are closed", async (t) => {
  const root = await mkdtemp(join(tmpdir(), "blender-contract-")); t.after(() => rm(root, { recursive: true, force: true }));
  await chmod(root, 0o700);
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

test("fake Blender receives exact argv and a closed request without path keyword false positives", async (t) => {
  let invocation;
  const { outputRoot, fakeBlender, observed, result } = await runFakeConversion(t, { onExport: ({ args, request }) => {
    invocation = { args: [...args], request, mode: statSync(args.at(-1)).mode & 0o777 };
    writeFileSync(request.outputPrivatePath, "deterministic glb");
    writeFileSync(request.resultPrivatePath, '{"sourceActionNames":["Idle"]}\n');
    return { status: 0, stdout: "" };
  } });
  assert.equal(observed.length, 1);
  assert.deepEqual(invocation.args, ["--background", "--factory-startup", "--python-exit-code", "1", "--python", exporterPath, "--", invocation.args.at(-1)]);
  assert.equal(invocation.args.filter((argument) => argument === "--").length, 1);
  assert.equal(invocation.mode, 0o600);
  assert.equal(dirname(invocation.args.at(-1)).startsWith(outputRoot), true);
  assert.deepEqual(Object.keys(invocation.request).sort(), ["atlasBasename", "atlasDigest", "category", "id", "outputPrivatePath", "policy", "resultPrivatePath", "scale", "sourceBasename"]);
  assert.match(invocation.request.outputPrivatePath, /home-cache/u);
  assert.equal(Object.hasOwn(invocation.request, "cache"), false);
  assert.equal(Object.hasOwn(invocation.request, "token"), false);
  assert.equal(Object.hasOwn(invocation.request, "network"), false);
  assert.equal(invocation.request.scale, 0.45);
  assert.deepEqual(invocation.request.policy, { animation: "retain_names_for_future_validation", texture: "material_color_only" });
  const manifestBytes = await readFile(join(outputRoot, "conversion-run-manifest.json"));
  const manifest = JSON.parse(manifestBytes);
  assert.deepEqual(manifestBytes, canonicalBytes(manifest));
  assert.equal(manifestBytes.subarray(-1).toString(), "\n");
  assert.equal(result.manifestDigest, digest(manifestBytes));
  assert.equal(manifest.models[0].output.logicalPath, "assets/models/tank/tank2.glb");
  assert.equal(manifest.models[0].scale, 0.45);
  assert.deepEqual(manifest.models[0].policy, { animation: "retain_names_for_future_validation", texture: "material_color_only" });
  assert.deepEqual(manifest.models[0].sourceActionNames, ["Idle"]);
  assert.equal(JSON.stringify(manifest).includes(outputRoot), false);
  assert.equal(fakeBlender.length > 0, true);
});

test("partial, unexpected, and caller-output collisions fail without published assets or manifest", async (t) => {
  for (const mode of ["partial", "unexpected"]) {
    const fixture = await createFixture(t, { rootSuffix: `conversion-${mode}` });
    await assert.rejects(runFakeConversion(t, { fixture, onExport: ({ request }) => {
      if (mode === "unexpected") {
        writeFileSync(request.outputPrivatePath, "glb");
        writeFileSync(request.resultPrivatePath, '{"sourceActionNames":["Idle"]}\n');
        writeFileSync(join(dirname(request.outputPrivatePath), "unexpected.txt"), "nope");
      }
      return { status: 0, stdout: "" };
    } }), { name: "ConversionError", message: "EXPORT_OUTPUT_INVALID" });
    assert.deepEqual(await readdir(fixture.outputRoot), []);
  }
  const fixture = await createFixture(t, { rootSuffix: "conversion-collision" });
  await writeFile(join(fixture.outputRoot, "existing"), "collision");
  await assert.rejects(runConversion({ assetLock: { models: [fixture.model] }, toolchainLock: fixture.toolchainLock, assetLockDigest: "d", toolchainLockDigest: "e", outputRoot: fixture.outputRoot, itemIds: ["tank2"], stageItem: fixture.stageItem, blenderPath: fixture.fakeBlender, exporterPath, runProcess: versionOrExport(fixture.fakeBlender, () => { throw new Error("must not start Blender"); }) }), { message: "OUTPUT_COLLISION" });
  assert.equal(await readFile(join(fixture.outputRoot, "existing"), "utf8"), "collision");
});

test("a non-zero exporter result is classified as EXPORT_FAILED before output validation", async (t) => {
  const fixture = await createFixture(t, { rootSuffix: "conversion-export-failure" });
  await assert.rejects(runFakeConversion(t, { fixture, onExport: ({ request }) => {
    writeFileSync(request.outputPrivatePath, "glb");
    writeFileSync(request.resultPrivatePath, '{"sourceActionNames":["Idle"]}\\n');
    return { status: 1, stdout: "Traceback (most recent call last):" };
  } }), { name: "ConversionError", message: "EXPORT_FAILED" });
  assert.deepEqual(await readdir(fixture.outputRoot), []);
});

test("exporter loads a valid lazy building image only after its strict staging checks", async () => {
  const probe = String.raw`
import hashlib
import importlib.util
import sys
import tempfile
import types
from pathlib import Path

class Image:
    def __init__(self, filepath, behavior):
        self.filepath = filepath
        self.behavior = behavior
        self.has_data = False
        self.events = []
    def reload(self):
        self.events.append("reload")
        if self.behavior == "failed-load":
            raise ValueError("simulated Blender load failure")
    @property
    def pixels(self):
        self.events.append("pixel")
        if self.behavior == "lazy":
            self.has_data = True
        return [0.0]

with tempfile.TemporaryDirectory() as temporary:
    request_dir = Path(temporary)
    atlas = request_dir / "Texture.png"
    atlas.write_bytes(b"atlas")
    bpy = types.SimpleNamespace(path=types.SimpleNamespace(abspath=lambda _: str(atlas)))
    sys.modules["bpy"] = bpy
    spec = importlib.util.spec_from_file_location("exporter", sys.argv[1])
    exporter = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(exporter)
    request = {"category": "building", "id": "1story", "atlasBasename": "Texture.png", "atlasDigest": hashlib.sha256(atlas.read_bytes()).hexdigest()}
    for behavior, filepath, expected in [
        ("lazy", "//Texture.png", None),
        ("missing", "//Texture.png", "atlas must be staged"),
        ("escaped", "//Texture.png", "building image escaped staging"),
        ("wrong-path", "//Other.png", "building image path contract"),
        ("failed-load", "//Texture.png", "building image load failed"),
    ]:
        image = Image(filepath, behavior)
        exporter.used_images = lambda: [image]
        if behavior == "missing":
            atlas.unlink()
        elif behavior == "escaped":
            bpy.path.abspath = lambda _: str(request_dir / "outside" / "Texture.png")
        try:
            exporter.verify_images(request_dir, request)
            assert expected is None, behavior
            assert image.events == ["reload", "pixel"], image.events
            assert image.has_data
        except RuntimeError as error:
            assert str(error) == expected, (behavior, str(error))
            assert image.events == ([] if behavior in {"missing", "escaped", "wrong-path"} else ["reload"]), (behavior, image.events)
        finally:
            if behavior == "missing":
                atlas.write_bytes(b"atlas")
            bpy.path.abspath = lambda _: str(atlas)
`;
  const result = spawnSync("python3", ["-c", probe, exporterPath], {
    encoding: "utf8", env: { ...process.env, PYTHONDONTWRITEBYTECODE: "1" },
  });
  assert.equal(result.status, 0, result.stderr);
});

test("the same fake output has stable GLB and consumer manifest digests across full conversions", async (t) => {
  const one = await runFakeConversion(t, { });
  const two = await runFakeConversion(t, { });
  const oneManifest = await readFile(join(one.outputRoot, "conversion-run-manifest.json"));
  const twoManifest = await readFile(join(two.outputRoot, "conversion-run-manifest.json"));
  assert.deepEqual(oneManifest, twoManifest);
  assert.equal(one.result.manifestDigest, digest(oneManifest));
  assert.equal(two.result.manifestDigest, digest(twoManifest));
  assert.equal(digest(await readFile(join(one.outputRoot, "assets/models/tank/tank2.glb"))), digest(await readFile(join(two.outputRoot, "assets/models/tank/tank2.glb"))));
});

test("ConversionError codes remain closed", () => {
  assert.equal(new ConversionError("not-a-code").code, "CONVERSION_FAILED");
  for (const code of ["USAGE", "MODEL_ID_INVALID", "OUTPUT_COLLISION", "EXPORT_OUTPUT_INVALID", "BLENDER_VERSION_MISMATCH"]) assert.equal(CONVERSION_ERROR_CODES.has(code), true);
});

test("exporter compiles outside the repository and pins source contracts without repo bytecode", async (t) => {
  const before = spawnSync("git", ["status", "--porcelain", "--untracked-files=all"], { encoding: "utf8" });
  assert.equal(before.status, 0, before.stderr);
  const root = await mkdtemp(join(tmpdir(), "exporter-pyc-"));
  await chmod(root, 0o700);
  t.after(async () => { await rm(root, { recursive: true, force: true }); });
  const cfile = join(root, "exporter.pyc");
  const compiled = spawnSync("python3", ["-c", "import py_compile,sys; py_compile.compile(sys.argv[1], cfile=sys.argv[2], doraise=True)", exporterPath, cfile], { encoding: "utf8" });
  assert.equal(compiled.status, 0, compiled.stderr);
  assert.equal((statSync(root).mode & 0o777), 0o700);
  const exporter = await readFile(exporterPath, "utf8");
  assert.match(exporter, /REQUEST_FIELDS = \{/u);
  assert.match(exporter, /"outputPrivatePath",\s*\n\s*"policy", "resultPrivatePath", "scale", "sourceBasename"/u);
  assert.match(exporter, /CLOSED_IDS = \{/u);
  assert.match(exporter, /BUILDING_IMAGE_PATH = "\/\/Texture\.png"/u);
  for (const [option, value] of [["export_format", '"GLB"'], ["export_yup", "True"], ["use_selection", "True"], ["export_apply", "True"], ["export_materials", '"EXPORT"'], ["export_draco_mesh_compression_enable", "False"]]) {
    assert.match(exporter, new RegExp(`"${option}": ${value}`, "u"));
  }
  await rm(root, { recursive: true, force: true });
  const after = spawnSync("git", ["status", "--porcelain", "--untracked-files=all"], { encoding: "utf8" });
  assert.equal(after.status, 0, after.stderr);
  assert.equal(after.stdout, before.stdout);
});
