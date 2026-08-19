import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { loadAndValidateAssetLock, runAssetLockCli, validateAssetLockText, validateAssetLockValue } from "../scripts/validate-assets-lock.mjs";

const fixtureText = readFileSync(new URL("../docs/assets/quaternius-lock.json", import.meta.url), "utf8");
const fixture = JSON.parse(fixtureText);

function lock() {
  return structuredClone(fixture);
}

function expectPath(mutator, path) {
  const value = lock();
  mutator(value);
  assert.throws(() => validateAssetLockValue(value), { message: path });
}

function stream() {
  let text = "";
  return { writable: { write: (chunk) => { text += chunk; } }, text: () => text };
}

test("accepts the committed absent lock through text and value validators", () => {
  assert.equal(validateAssetLockText(fixtureText).models.length, 9);
  assert.equal(validateAssetLockValue(lock()).atlases.length, 1);
});

test("text layer rejects empty, BOM, malformed, and non-object roots", () => {
  for (const text of ["", `\uFEFF${fixtureText}`, "{ nope"]) {
    assert.throws(() => validateAssetLockText(text), { message: "text" });
  }
  for (const text of ["null", "[]", "1"]) assert.throws(() => validateAssetLockText(text));
});

test("closed schemas reject unknown, missing, and prototype-named fields at every layer", () => {
  const cases = [
    [(value) => { value.extra = true; }, "extra"],
    [(value) => { delete value.coordinateContract.source; }, "coordinateContract.source"],
    [(value) => { value.coordinateContract.axisTolerance.constructor = true; }, "coordinateContract.axisTolerance.constructor"],
    [(value) => { value.conversionManifest.prototype = true; }, "conversionManifest.prototype"],
    [(value) => { Object.defineProperty(value.conversionManifest.requirementsWhenPresent, "__proto__", { value: true, enumerable: true }); }, "conversionManifest.requirementsWhenPresent.__proto__"],
    [(value) => { value.models[0].unknown = true; }, "models[0].unknown"],
    [(value) => { delete value.models[0].source.fileId; }, "models[0].source.fileId"],
    [(value) => { value.atlases[0].constructor = true; }, "atlases[0].constructor"],
  ];
  for (const [mutate, path] of cases) expectPath(mutate, path);
});

test("rejects non-finite, negative zero, and unsafe integer numeric values", () => {
  for (const [mutate, path] of [
    [(value) => { value.models[0].scale = NaN; }, "models[0].scale"],
    [(value) => { value.models[0].rawSourceXyz[0] = Infinity; }, "models[0].rawSourceXyz[0]"],
    [(value) => { value.models[0].expectedGodotXyz[0] = -0; }, "models[0].expectedGodotXyz[0]"],
    [(value) => { value.models[0].source.sizeBytes = Number.MAX_SAFE_INTEGER + 1; }, "models[0].source.sizeBytes"],
    [(value) => { value.atlases[0].sizeBytes = -0; }, "atlases[0].sizeBytes"],
  ]) expectPath(mutate, path);
});

test("rejects invalid identity formats, filenames, and normalized collisions", () => {
  for (const [mutate, path] of [
    [(value) => { value.models[0].pack = "other"; }, "models[0].pack"],
    [(value) => { value.models[1].category = "tankish"; }, "models[1].category"],
    [(value) => { value.models[0].source.fileId = "short"; }, "models[0].source.fileId"],
    [(value) => { value.models[0].source.sha256 = "A".repeat(64); }, "models[0].source.sha256"],
    [(value) => { value.models[0].source.sizeBytes = 0; }, "models[0].source.sizeBytes"],
    [(value) => { value.models[1].id = " 1story"; }, "models[1].id"],
    [(value) => { value.models[1].source.filename = "1Story\n.blend"; }, "models[1].source.filename"],
    [(value) => { value.models[0].source.filename = "../Tank2.blend"; }, "models[0].source.filename"],
    [(value) => { value.atlases[0].filename = "Texture\\Light.png"; }, "atlases[0].filename"],
    [(value) => { value.models[1].id = "TANK2"; }, "models[1]"],
    [(value) => { value.models[1].source.filename = value.models[0].source.filename.toLowerCase(); }, "models[1]"],
  ]) expectPath(mutate, path);
});

test("enforces mapping, scale, coordinate contract, manifest, count, and policies", () => {
  for (const [mutate, path] of [
    [(value) => { value.models[0].expectedGodotXyz[0] += 0.00001; }, "models[0].expectedGodotXyz[0]"],
    [(value) => {
      const model = value.models[0];
      model.expectedGodotXyz = [model.rawSourceXyz[0] * model.scale, model.rawSourceXyz[1] * model.scale, model.rawSourceXyz[2] * model.scale]
        .map((axis) => Math.round(axis * 100000) / 100000);
    }, "models[0].expectedGodotXyz[1]"],
    [(value) => {
      const model = value.models[0];
      model.scale = 0.46;
      model.expectedGodotXyz = [model.rawSourceXyz[0] * model.scale, model.rawSourceXyz[2] * model.scale, model.rawSourceXyz[1] * model.scale]
        .map((axis) => Math.round(axis * 100000) / 100000);
    }, "models[0]"],
    [(value) => { value.coordinateContract.axisTolerance.relative = 0.01; }, "coordinateContract.axisTolerance.relative"],
    [(value) => { value.conversionManifest.requiredModelFieldsWhenPresent.reverse(); }, "conversionManifest.requiredModelFieldsWhenPresent[0]"],
    [(value) => { value.models.splice(1, 1); }, "models"],
    [(value) => { value.models[1].category = "tank"; }, "models[1]"],
    [(value) => { value.models[1].texturePolicy = "material_color_only"; }, "models[1]"],
    [(value) => { value.models[1].sourceImagePath = "//Other.png"; }, "models[1]"],
    [(value) => { value.atlases[0].stagingBasename = "Other.png"; }, "atlases[0].stagingBasename"],
    [(value) => { value.models.push(structuredClone(value.models[1])); }, "models"],
  ]) expectPath(mutate, path);
});

test("enforces absent and present conversion state invariants", () => {
  expectPath((value) => { value.models[0].outputDigest = "a".repeat(64); }, "models[0]");
  expectPath((value) => { value.models[1].measuredGodotXyz = [...value.models[1].expectedGodotXyz]; }, "models[1]");
  expectPath((value) => { value.models[1].embeddedImageDigest = "a".repeat(64); }, "models[1]");
  expectPath((value) => { value.models[0].embeddedImageDigest = "a".repeat(64); }, "models[0]");

  const present = lock();
  present.conversionManifest.state = "present";
  for (const model of present.models) {
    model.outputDigest = "a".repeat(64);
    model.measuredGodotXyz = [...model.expectedGodotXyz];
    if (model.category === "building") model.embeddedImageDigest = "b".repeat(64);
  }
  assert.doesNotThrow(() => validateAssetLockValue(present));
  present.models[1].measuredGodotXyz[0] += 1;
  assert.throws(() => validateAssetLockValue(present), { message: "models[1].measuredGodotXyz[0]" });
});

test("loader and CLI seam redact paths and emit one JSON line", async (t) => {
  const directory = await mkdtemp(join(tmpdir(), "asset-lock-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const invalid = join(directory, "invalid.json");
  await writeFile(invalid, "{ nope", "utf8");
  await assert.rejects(loadAndValidateAssetLock(invalid), (error) => error.code === "parse_error" && error.path === "text");
  const stdout = stream();
  const stderr = stream();
  assert.equal(await runAssetLockCli(["--check"], { lockPath: invalid, stdout: stdout.writable, stderr: stderr.writable }), 1);
  assert.equal(stdout.text(), "");
  assert.equal(stderr.text(), '{"ok":false,"code":"parse_error","path":"text"}\n');
});

test("CLI is cwd-independent, exact in arguments, and import is silent", async (t) => {
  const directory = await mkdtemp(join(tmpdir(), "asset-lock-cwd-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const scriptPath = fileURLToPath(new URL("../scripts/validate-assets-lock.mjs", import.meta.url));
  const valid = spawnSync(process.execPath, [scriptPath, "--check"], { cwd: directory, encoding: "utf8" });
  if (valid.error?.code === "EPERM") {
    t.skip("execution sandbox blocks nested process creation");
    return;
  }
  assert.equal(valid.status, 0);
  assert.equal(valid.stdout, '{"ok":true,"schemaVersion":1,"models":9,"atlases":1}\n');
  assert.equal(valid.stderr, "");
  for (const args of [[], ["--bad"], ["--check", "extra"]]) {
    const result = spawnSync(process.execPath, [scriptPath, ...args], { cwd: directory, encoding: "utf8" });
    assert.equal(result.status, 2);
    assert.equal(result.stdout, "");
    assert.equal(result.stderr, '{"ok":false,"code":"usage_error","path":"argv"}\n');
  }
  const moduleUrl = new URL("../scripts/validate-assets-lock.mjs", import.meta.url).href;
  const imported = spawnSync(process.execPath, ["--input-type=module", "--eval", `import ${JSON.stringify(moduleUrl)};`], { encoding: "utf8" });
  assert.equal(imported.status, 0);
  assert.equal(imported.stdout, "");
  assert.equal(imported.stderr, "");
});
