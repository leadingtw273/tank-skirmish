import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFile, mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { validateAssetLockText, validateAssetLockValue } from "../scripts/validate-assets-lock.mjs";

const sourceText = readFileSync(new URL("../docs/assets/quaternius-lock.json", import.meta.url), "utf8");
const fixture = JSON.parse(sourceText);

function lock() {
  return structuredClone(fixture);
}

function expectReject(mutator, path) {
  const value = lock();
  mutator(value);
  assert.throws(() => validateAssetLockValue(value), { message: path });
}

function building(value = lock()) {
  return value.models.find((model) => model.category === "building");
}

function present(value = lock()) {
  value.conversionManifest.state = "present";
  for (const model of value.models) {
    model.outputDigest = "a".repeat(64);
    model.measuredGodotXyz = [...model.expectedGodotXyz];
    model.embeddedImageDigest = model.category === "building" ? "b".repeat(64) : null;
  }
  return value;
}

test("accepts the committed absent lock and a fully-populated present lock", () => {
  assert.equal(validateAssetLockText(sourceText).schemaVersion, 1);
  assert.equal(validateAssetLockValue(present()).conversionManifest.state, "present");
});

test("rejects text failures and non-object roots", () => {
  for (const text of ["", "\uFEFF{}", "{ nope", "null", "[]", "1", "\"lock\""]) {
    assert.throws(() => validateAssetLockText(text));
  }
});

test("rejects closed-schema unknown, missing, and prototype keys at every object layer", () => {
  const cases = [
    [(value) => { value.extra = true; }, "extra"],
    [(value) => { delete value.models; }, "models"],
    [(value) => { value.coordinateContract.extra = true; }, "coordinateContract.extra"],
    [(value) => { delete value.coordinateContract.axisTolerance.relative; }, "coordinateContract.axisTolerance.relative"],
    [(value) => { value.conversionManifest.constructor = 1; }, "conversionManifest.constructor"],
    [(value) => { value.conversionManifest.requirementsWhenPresent.prototype = 1; }, "conversionManifest.requirementsWhenPresent.prototype"],
    [(value) => { building(value).unknown = true; }, "models[1].unknown"],
    [(value) => { delete building(value).source.fileId; }, "models[1].source.fileId"],
    [(value) => { value.atlases[0].__proto__ = { polluted: true }; }, "atlases[0]"],
  ];
  for (const [mutate, path] of cases) expectReject(mutate, path);
});

test("rejects invalid primitive values, identity fields, filenames, and normalized collisions", () => {
  const cases = [
    [(value) => { building(value).source.sizeBytes = Number.NaN; }, "models[1].source.sizeBytes"],
    [(value) => { building(value).rawSourceXyz[0] = Infinity; }, "models[1].rawSourceXyz[0]"],
    [(value) => { building(value).scale = -0; }, "models[1].scale"],
    [(value) => { building(value).source.sizeBytes = Number.MAX_SAFE_INTEGER + 1; }, "models[1].source.sizeBytes"],
    [(value) => { building(value).pack = "other"; }, "models[1].pack"],
    [(value) => { building(value).category = "atlas"; }, "models[1].category"],
    [(value) => { building(value).source.fileId = "x".repeat(32); }, "models[1].source.fileId"],
    [(value) => { building(value).source.sha256 = "A".repeat(64); }, "models[1].source.sha256"],
    [(value) => { building(value).source.sizeBytes = 0; }, "models[1].source.sizeBytes"],
    [(value) => { building(value).source.filename = "../Tank2.blend"; }, "models[1].source.filename"],
    [(value) => { value.atlases[0].filename = "C:\\Texture.png"; }, "atlases[0].filename"],
    [(value) => { value.atlases[0].stagingBasename = "texture.png"; }, "atlases[0].stagingBasename"],
    [(value) => { building(value).id = value.models[2].id.toUpperCase(); }, "models[2]"],
    [(value) => {
      const filename = value.models[2].source.filename;
      building(value).source.filename = `${filename.slice(0, -6).toUpperCase()}.blend`;
    }, "models[2]"],
  ];
  for (const [mutate, path] of cases) expectReject(mutate, path);
});

test("enforces coordinate contract, deterministic axis mapping, and category policy", () => {
  const cases = [
    [(value) => { value.coordinateContract.axisTolerance.relative = 0.01; }, "coordinateContract.axisTolerance.relative"],
    [(value) => {
      const model = building(value);
      model.scale = 0.45;
      model.expectedGodotXyz = [model.rawSourceXyz[0], model.rawSourceXyz[2], model.rawSourceXyz[1]].map((axis) => Math.round(axis * model.scale * 100000) / 100000);
    }, "models[1]"],
    [(value) => { building(value).expectedGodotXyz = [...building(value).expectedGodotXyz].reverse(); }, "models[1].expectedGodotXyz[0]"],
    [(value) => { building(value).expectedGodotXyz[0] += 0.000001; }, "models[1].expectedGodotXyz[0]"],
    [(value) => { building(value).animationPolicy = "retain_names_for_future_validation"; }, "models[1]"],
    [(value) => { building(value).sourceImagePath = "//other.png"; }, "models[1]"],
    [(value) => { value.models[0].embeddedImageDigest = "a".repeat(64); }, "models[0].embeddedImageDigest"],
  ];
  for (const [mutate, path] of cases) expectReject(mutate, path);
});

test("separates models from atlases and applies final category counts after model validation", () => {
  expectReject((value) => { value.models[1] = structuredClone(value.atlases[0]); }, "models[1].category");
  expectReject((value) => { value.models[1] = structuredClone(value.models[0]); }, "models");
  expectReject((value) => { value.models[0] = structuredClone(value.models[1]); }, "models");
  expectReject((value) => { value.models.pop(); }, "models");
});

test("enforces absent and present conversion-state invariants", () => {
  const absentCases = [
    [(value) => { building(value).outputDigest = "a".repeat(64); }, "models[1].outputDigest"],
    [(value) => { building(value).measuredGodotXyz = [...building(value).expectedGodotXyz]; }, "models[1].measuredGodotXyz"],
    [(value) => { building(value).embeddedImageDigest = "a".repeat(64); }, "models[1].embeddedImageDigest"],
  ];
  for (const [mutate, path] of absentCases) expectReject(mutate, path);

  for (const [mutate, path] of [
    [(value) => { building(value).outputDigest = null; }, "models[1].outputDigest"],
    [(value) => { building(value).embeddedImageDigest = "A".repeat(64); }, "models[1].embeddedImageDigest"],
    [(value) => { building(value).measuredGodotXyz[0] += 1; }, "models[1].measuredGodotXyz[0]"],
    [(value) => { value.models[0].embeddedImageDigest = "b".repeat(64); }, "models[0].embeddedImageDigest"],
  ]) {
    const value = present();
    mutate(value);
    assert.throws(() => validateAssetLockValue(value), { message: path });
  }
});

test("import is silent and CLI is cwd-independent with exact stream contracts", async (t) => {
  const directory = await mkdtemp(join(tmpdir(), "assets-lock-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const script = fileURLToPath(new URL("../scripts/validate-assets-lock.mjs", import.meta.url));
  const importResult = spawnSync(process.execPath, ["--input-type=module", "--eval", `import ${JSON.stringify(new URL("../scripts/validate-assets-lock.mjs", import.meta.url).href)};`], { encoding: "utf8" });
  if (importResult.error?.code === "EPERM") return t.skip("execution sandbox blocks nested process creation");
  assert.deepEqual([importResult.status, importResult.stdout, importResult.stderr], [0, "", ""]);

  const valid = spawnSync(process.execPath, [script, "--check"], { cwd: directory, encoding: "utf8" });
  assert.deepEqual([valid.status, valid.stdout, valid.stderr], [0, "{\"ok\":true,\"schemaVersion\":1,\"models\":9,\"atlases\":1}\n", ""]);
  for (const args of [[], ["--wrong"], ["--check", "extra"]]) {
    const usage = spawnSync(process.execPath, [script, ...args], { cwd: directory, encoding: "utf8" });
    assert.deepEqual([usage.status, usage.stdout, usage.stderr], [2, "", "{\"ok\":false,\"code\":\"usage_error\",\"path\":\"argv\"}\n"]);
  }

  const copiedScript = join(directory, "scripts", "validate-assets-lock.mjs");
  const invalidLock = join(directory, "docs", "assets", "quaternius-lock.json");
  await mkdir(dirname(copiedScript), { recursive: true });
  await mkdir(dirname(invalidLock), { recursive: true });
  await copyFile(script, copiedScript);
  const invalid = lock();
  invalid.schemaVersion = 2;
  await writeFile(invalidLock, JSON.stringify(invalid), "utf8");
  const invalidResult = spawnSync(process.execPath, [copiedScript, "--check"], { cwd: join(directory, "scripts"), encoding: "utf8" });
  assert.equal(invalidResult.status, 1);
  assert.equal(invalidResult.stdout, "");
  assert.equal(invalidResult.stderr, "{\"ok\":false,\"code\":\"validation_error\",\"path\":\"schemaVersion\"}\n");
  assert.doesNotMatch(invalidResult.stderr, new RegExp(directory.replace(/[.*+?^${}()|[\]\\]/gu, "\\$&"), "u"));
});
