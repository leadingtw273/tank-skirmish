import assert from "node:assert/strict";
import { mkdtemp, mkdir, readdir, rm, stat, symlink, writeFile } from "node:fs/promises";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  ToolCacheResolutionError,
  downloadPinnedArchive,
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

function response(status, { location, body = [] } = {}) {
  return {
    status,
    headers: location === undefined ? {} : { location },
    body: (async function* stream() {
      yield* body;
    })(),
  };
}

function transportFrom(...responses) {
  const requests = [];
  return {
    requests,
    transport: {
      async open(url) {
        requests.push(url);
        const next = responses.shift();
        if (next instanceof Error) throw next;
        return next;
      },
    },
  };
}

async function expectDownloadFailure(action, code) {
  await assert.rejects(action, (error) => error instanceof ToolCacheResolutionError && error.code === code);
}

async function temporaryCache(t) {
  const directory = await mkdtemp(join(tmpdir(), "toolchain-download-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  return directory;
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

test("rejects every Blender redirect without following it", async (t) => {
  const cacheRoot = await temporaryCache(t);
  const setup = transportFrom(response(302, { location: "https://release-assets.githubusercontent.com/github-production-release-asset/example" }));

  await expectDownloadFailure(() => downloadPinnedArchive("blender", { cacheRoot, transport: setup.transport }), "network_rejected");
  assert.equal(setup.requests.length, 1);
});

test("rejects Godot redirects with unpinned destinations or a second redirect", async (t) => {
  const cacheRoot = await temporaryCache(t);
  const permanentRedirect = transportFrom(response(301, { location: "https://release-assets.githubusercontent.com/github-production-release-asset/sample" }));
  await expectDownloadFailure(() => downloadPinnedArchive("godot", { cacheRoot, transport: permanentRedirect.transport }), "network_rejected");
  assert.equal(permanentRedirect.requests.length, 1);

  const locations = [
    "https://example.com/github-production-release-asset/sample",
    "https://release-assets.githubusercontent.com/not-github-production-release-asset/sample",
    "/github-production-release-asset/relative",
  ];

  for (const location of locations) {
    const setup = transportFrom(response(302, { location }));
    await expectDownloadFailure(() => downloadPinnedArchive("godot", { cacheRoot, transport: setup.transport }), "network_rejected");
    assert.equal(setup.requests.length, 1);
  }

  const setup = transportFrom(
    response(307, { location: "https://release-assets.githubusercontent.com/github-production-release-asset/sample" }),
    response(302, { location: "https://release-assets.githubusercontent.com/github-production-release-asset/fake" }),
  );
  await expectDownloadFailure(() => downloadPinnedArchive("godot", { cacheRoot, transport: setup.transport }), "network_rejected");
  assert.equal(setup.requests.length, 2);
});

test("permits one signed Godot CDN redirect without serializing its query", async (t) => {
  const cacheRoot = await temporaryCache(t);
  const signedLocation = "https://release-assets.githubusercontent.com/github-production-release-asset/sample?X-Amz-Credential=example-placeholder&X-Amz-Signature=fake";
  const setup = transportFrom(response(303, { location: signedLocation }), response(503));

  await assert.rejects(
    () => downloadPinnedArchive("godot", { cacheRoot, transport: setup.transport }),
    (error) => {
      assert.equal(error.code, "network_rejected");
      assert.doesNotMatch(error.message, /X-Amz-|example-placeholder|fake/u);
      assert.doesNotMatch(JSON.stringify(error), /X-Amz-|example-placeholder|fake/u);
      return true;
    },
  );
  assert.deepEqual(setup.requests, [
    "https://github.com/godotengine/godot-builds/releases/download/4.7.1-stable/Godot_v4.7.1-stable_linux.x86_64.zip",
    signedLocation,
  ]);
});

test("rejects incorrect archive sizes and digests", async (t) => {
  const cacheRoot = await temporaryCache(t);
  const shortBody = transportFrom(response(200, { body: [new Uint8Array([1])] }));
  await expectDownloadFailure(() => downloadPinnedArchive("godot", { cacheRoot, transport: shortBody.transport }), "verification_failed");

  const exactSizeWrongDigest = transportFrom(response(200, { body: [new Uint8Array(76056717)] }));
  await expectDownloadFailure(() => downloadPinnedArchive("godot", { cacheRoot, transport: exactSizeWrongDigest.transport }), "verification_failed");
});

test("uses a private 0700 staging transaction and removes only its failed UUID", async (t) => {
  const cacheRoot = await temporaryCache(t);
  const sibling = join(cacheRoot, ".staging", "00000000-0000-4000-8000-000000000000");
  await mkdir(sibling, { recursive: true, mode: 0o700 });
  let snapshot;
  const partialBody = {
    async *[Symbol.asyncIterator]() {
      yield new Uint8Array([1]);
      const stagingRoot = join(cacheRoot, ".staging");
      const entries = await readdir(stagingRoot);
      const transactionId = entries.find((entry) => entry !== "00000000-0000-4000-8000-000000000000");
      const transactionRoot = join(stagingRoot, transactionId);
      snapshot = {
        rootMode: (await stat(transactionRoot)).mode & 0o777,
        archiveExists: (await stat(join(transactionRoot, "download", "archive"))).isFile(),
        treeExists: (await stat(join(transactionRoot, "download", "tree"))).isDirectory(),
      };
      throw new Error("partial stream");
    },
  };
  const setup = transportFrom({ status: 200, headers: {}, body: partialBody });

  await expectDownloadFailure(() => downloadPinnedArchive("godot", { cacheRoot, transport: setup.transport }), "network_rejected");
  assert.deepEqual(snapshot, { rootMode: 0o700, archiveExists: true, treeExists: true });
  assert.deepEqual(await readdir(join(cacheRoot, ".staging")), ["00000000-0000-4000-8000-000000000000"]);
});

test("bootstrap module uses only the built-in HTTPS transport", () => {
  const source = readFileSync(scriptPath, "utf8");
  assert.match(source, /node:https/u);
  assert.doesNotMatch(source, /node:http(?=["'])|node:(?:net|tls|dgram|dns|child_process)|\bfetch\s*\(/u);
  assert.doesNotMatch(source, /\bgit\b/u);
});
