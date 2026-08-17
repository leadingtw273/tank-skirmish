import assert from "node:assert/strict";
import { mkdtemp, rm, symlink, writeFile } from "node:fs/promises";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  ToolCacheResolutionError,
  resolveCacheTarget,
  resolveToolCacheRoot,
  runBootstrapToolchainCli,
} from "../scripts/bootstrap-toolchain.mjs";

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const scriptPath = fileURLToPath(new URL("../scripts/bootstrap-toolchain.mjs", import.meta.url));

function expectResolutionError(action, code) {
  assert.throws(action, (error) => error instanceof ToolCacheResolutionError && error.code === code);
}

function memoryStream() {
  let value = "";
  return {
    stream: { write: (chunk) => { value += chunk; } },
    value: () => value,
  };
}

test("resolves configured and XDG cache roots without consulting git", async (t) => {
  const directory = await mkdtemp(join(tmpdir(), "toolchain-bootstrap-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const configured = join(directory, "configured", "not-created-yet");
  const xdg = join(directory, "xdg");

  assert.equal(resolveToolCacheRoot({ TANK_SKIRMISH_TOOL_CACHE: configured }), configured);
  assert.equal(resolveToolCacheRoot({ XDG_CACHE_HOME: xdg }), join(xdg, "tank-skirmish", "toolchains"));
  assert.equal(resolveCacheTarget("godot", { cacheRoot: configured }), join(configured, "godot", "4.7.1-stable"));
  assert.equal(resolveCacheTarget("blender", { cacheRoot: configured }), join(configured, "blender", "4.5.12"));
});

test("rejects relative, repository-contained, and symlinked cache roots", async (t) => {
  const directory = await mkdtemp(join(tmpdir(), "toolchain-bootstrap-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const repositoryInternal = join(projectRoot, "temporary-cache-root");
  const symlinkPath = join(directory, "repository-link");
  const brokenSymlinkPath = join(directory, "broken-link");
  const filePath = join(directory, "not-a-directory");
  await symlink(projectRoot, symlinkPath, "dir");
  await symlink(join(directory, "missing-target"), brokenSymlinkPath, "dir");
  await writeFile(filePath, "not a directory", "utf8");

  expectResolutionError(() => resolveToolCacheRoot({ TANK_SKIRMISH_TOOL_CACHE: "relative-cache" }), "invalid_cache_root");
  expectResolutionError(() => resolveToolCacheRoot({ TANK_SKIRMISH_TOOL_CACHE: projectRoot }), "repository_containment");
  expectResolutionError(() => resolveToolCacheRoot({ TANK_SKIRMISH_TOOL_CACHE: repositoryInternal }), "repository_containment");
  expectResolutionError(() => resolveToolCacheRoot({ TANK_SKIRMISH_TOOL_CACHE: join(symlinkPath, "future-tail") }), "repository_containment");
  expectResolutionError(() => resolveToolCacheRoot({ TANK_SKIRMISH_TOOL_CACHE: brokenSymlinkPath }), "io_error");
  expectResolutionError(() => resolveToolCacheRoot({ TANK_SKIRMISH_TOOL_CACHE: filePath }), "io_error");
});

test("module CLI seam emits only sanitized JSON", async (t) => {
  const directory = await mkdtemp(join(tmpdir(), "toolchain-bootstrap-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const stdout = memoryStream();
  const stderr = memoryStream();

  assert.equal(runBootstrapToolchainCli(["--check-cache", "--tool", "godot", "--cache-dir", directory], {
    stdout: stdout.stream,
    stderr: stderr.stream,
  }), 0);
  assert.equal(stdout.value(), `${JSON.stringify({ tool: "godot", mode: "check_cache", state: "cache_target_valid", network: "unused" })}\n`);
  assert.equal(stderr.value(), "");

  const containedOut = memoryStream();
  const containedErr = memoryStream();
  assert.equal(runBootstrapToolchainCli(["--check-cache", "--tool", "godot", "--cache-dir", projectRoot], {
    stdout: containedOut.stream,
    stderr: containedErr.stream,
  }), 3);
  assert.equal(containedOut.value(), "");
  assert.equal(containedErr.value(), `${JSON.stringify({ ok: false, code: "cache_target_error" })}\n`);
});

test("child process validates default and explicit cache targets offline", async (t) => {
  const directory = await mkdtemp(join(tmpdir(), "toolchain-bootstrap-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const defaultEnvironment = { ...process.env };
  delete defaultEnvironment.TANK_SKIRMISH_TOOL_CACHE;
  delete defaultEnvironment.XDG_CACHE_HOME;

  for (const [argumentsList, environment] of [
    [["--check-cache", "--tool", "godot"], defaultEnvironment],
    [["--check-cache", "--tool", "blender", "--cache-dir", directory], process.env],
  ]) {
    const result = spawnSync(process.execPath, [scriptPath, ...argumentsList], {
      cwd: directory,
      encoding: "utf8",
      env: environment,
    });
    if (result.error?.code === "EPERM") {
      t.skip("execution sandbox blocks nested process creation");
      return;
    }
    assert.equal(result.status, 0);
    assert.equal(result.stderr, "");
    assert.deepEqual(JSON.parse(result.stdout), {
      tool: argumentsList[2],
      mode: "check_cache",
      state: "cache_target_valid",
      network: "unused",
    });
  }
});

test("child process rejects unknown, missing, and duplicate arguments", (t) => {
  for (const argumentsList of [
    ["--check-cache", "--tool"],
    ["--check-cache", "--tool", "unknown"],
    ["--check-cache", "--tool", "godot", "--tool", "blender"],
    ["--check-cache", "--tool", "godot", "--unknown"],
  ]) {
    const result = spawnSync(process.execPath, [scriptPath, ...argumentsList], { encoding: "utf8" });
    if (result.error?.code === "EPERM") {
      t.skip("execution sandbox blocks nested process creation");
      return;
    }
    assert.equal(result.status, 2);
    assert.equal(result.stdout, "");
    assert.equal(result.stderr, `${JSON.stringify({ ok: false, code: "usage_error" })}\n`);
  }
});

test("bootstrap module has no network dependencies", () => {
  const source = readFileSync(scriptPath, "utf8");
  assert.doesNotMatch(source, /node:(?:http|https|net|tls|dgram|dns|child_process)|\bfetch\s*\(/u);
  assert.doesNotMatch(source, /\bgit\b/u);
});
