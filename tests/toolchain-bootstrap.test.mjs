import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { mkdtemp, mkdir, readFile, readdir, rm, stat, symlink, writeFile } from "node:fs/promises";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  ToolCacheResolutionError,
  downloadPinnedArchive,
  installPinnedToolchain,
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

function fixtureTool(id, executableRelativePath, executableContents) {
  const executableDigest = createHash("sha256").update(executableContents).digest("hex");
  const godot = id === "godot";
  return {
    id,
    archive: {
      format: godot ? "zip" : "tar.xz",
      memberCount: 1,
      topLevelDirectory: godot ? null : "fixture-blender",
      exactMemberNames: godot ? [executableRelativePath] : null,
      allowedEntryTypes: godot ? ["regular_file"] : ["regular_file", "directory", "symlink"],
    },
    install: {
      executableRelativePath,
      executableChecksum: { algorithm: "sha256", value: executableDigest },
      versionContract: godot
        ? { mode: "exact_output", value: "4.7.1.stable.fixture" }
        : { mode: "first_line_and_build_hash", firstLine: "Blender 4.5.12 LTS", buildHash: "fixturehash12" },
    },
  };
}

function fixtureDownloader(contents) {
  const digest = createHash("sha512").update(contents).digest("hex");
  return async (_toolId, { cacheRoot }) => {
    const stagingRoot = join(cacheRoot, ".staging", randomUUID());
    const downloadDirectory = join(stagingRoot, "download");
    const archivePath = join(downloadDirectory, "archive");
    const treePath = join(stagingRoot, "tree");
    await mkdir(downloadDirectory, { recursive: true, mode: 0o700 });
    await mkdir(treePath, { mode: 0o700 });
    await writeFile(archivePath, contents);
    return { archivePath, treePath, archive: { sizeBytes: contents.length, algorithm: "sha512", digest } };
  };
}

function fixtureAdapter(executableRelativePath, executableContents) {
  return async ({ treePath }) => {
    const executablePath = join(treePath, ...executableRelativePath.split("/"));
    await mkdir(dirname(executablePath), { recursive: true, mode: 0o700 });
    await writeFile(executablePath, executableContents);
  };
}

function fixtureProcessRunner(tool) {
  return async () => ({
    code: 0,
    stdout: tool.install.versionContract.mode === "exact_output"
      ? `${tool.install.versionContract.value}\n`
      : `${tool.install.versionContract.firstLine}\nbuild hash: ${tool.install.versionContract.buildHash}\n`,
    stderr: "",
  });
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

  assert.equal(await runBootstrapToolchainCli(["--check-cache", "--tool", "godot", "--cache-dir", directory], {
    stdout: stdout.stream,
    stderr: stderr.stream,
  }), 0);
  assert.equal(stdout.value(), `${JSON.stringify({ tool: "godot", mode: "check_cache", state: "cache_target_valid", network: "unused" })}\n`);
  assert.equal(stderr.value(), "");

  const containedOut = memoryStream();
  const containedErr = memoryStream();
  assert.equal(await runBootstrapToolchainCli(["--check-cache", "--tool", "godot", "--cache-dir", projectRoot], {
    stdout: containedOut.stream,
    stderr: containedErr.stream,
  }), 3);
  assert.equal(containedOut.value(), "");
  assert.equal(containedErr.value(), `${JSON.stringify({ ok: false, code: "cache_target_error" })}\n`);
});

test("CLI accepts only help, cache-check, and install grammars without opening transport for usage", async (t) => {
  const directory = await mkdtemp(join(tmpdir(), "toolchain-bootstrap-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const helpOut = memoryStream();
  const helpErr = memoryStream();

  assert.equal(await runBootstrapToolchainCli(["--help"], {
    stdout: helpOut.stream,
    stderr: helpErr.stream,
  }), 0);
  assert.deepEqual(JSON.parse(helpOut.value()), {
    schemaVersion: 1,
    usage: "--help | --check-cache --tool <godot|blender> [--cache-dir <absolute-path>] | --install --tool <godot|blender> [--cache-dir <absolute-path>]",
  });
  assert.equal(helpErr.value(), "");

  let installCalls = 0;
  for (const argumentsList of [
    [],
    ["--help", "--install", "--tool", "godot"],
    ["--check-cache", "--install", "--tool", "godot"],
    ["--install", "--tool"],
    ["--install", "--tool", "unknown"],
    ["--install", "--tool", "godot", "--tool", "blender"],
    ["--install", "--tool", "godot", "--unknown"],
  ]) {
    const stdout = memoryStream();
    const stderr = memoryStream();
    assert.equal(await runBootstrapToolchainCli(argumentsList, {
      stdout: stdout.stream,
      stderr: stderr.stream,
      install: async () => { installCalls += 1; },
    }), 2);
    assert.equal(stdout.value(), "");
    assert.equal(stderr.value(), `${JSON.stringify({ ok: false, code: "usage_error" })}\n`);
  }
  assert.equal(installCalls, 0);
});

test("CLI serializes the install primitive result once", async (t) => {
  const directory = await mkdtemp(join(tmpdir(), "toolchain-bootstrap-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const stdout = memoryStream();
  const stderr = memoryStream();
  const result = {
    schemaVersion: 1,
    tool: "godot",
    state: "installed",
    network: "used",
    archive: { sizeBytes: 12, algorithm: "sha512", digest: "archive-digest" },
    executable: { algorithm: "sha256", digest: "executable-digest", version: "4.7.1.stable.fixture" },
  };
  let request;

  assert.equal(await runBootstrapToolchainCli(["--install", "--tool", "godot", "--cache-dir", directory], {
    stdout: stdout.stream,
    stderr: stderr.stream,
    install: async (toolId, options) => {
      request = { toolId, options };
      return result;
    },
  }), 0);
  assert.deepEqual(request, { toolId: "godot", options: { cacheRoot: directory } });
  assert.equal(stdout.value(), `${JSON.stringify(result)}\n`);
  assert.equal(stderr.value(), "");
});

test("CLI maps invalid and operational install failures to sanitized stderr JSON", async (t) => {
  const directory = await mkdtemp(join(tmpdir(), "toolchain-bootstrap-"));
  t.after(() => rm(directory, { recursive: true, force: true }));

  for (const [failure, code] of [
    [new ToolCacheResolutionError("install_invalid", join(directory, "corrupt-tool")), "install_invalid"],
    [new ToolCacheResolutionError("lock_timeout"), "lock_timeout"],
    [new Error(`transport failed for ${join(directory, "private-path")}`), "install_error"],
  ]) {
    const stdout = memoryStream();
    const stderr = memoryStream();
    assert.equal(await runBootstrapToolchainCli(["--install", "--tool", "godot", "--cache-dir", directory], {
      stdout: stdout.stream,
      stderr: stderr.stream,
      install: async () => { throw failure; },
    }), 3);
    assert.equal(stdout.value(), "");
    assert.equal(stderr.value(), `${JSON.stringify({ ok: false, code })}\n`);
    assert.doesNotMatch(stderr.value(), new RegExp(directory.replaceAll("/", "\\/"), "u"));
  }
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

test("child process rejects unknown, missing, mixed, and duplicate arguments", (t) => {
  for (const argumentsList of [
    ["--check-cache", "--tool"],
    ["--check-cache", "--tool", "unknown"],
    ["--check-cache", "--tool", "godot", "--tool", "blender"],
    ["--check-cache", "--tool", "godot", "--unknown"],
    ["--help", "--check-cache", "--tool", "godot"],
    ["--check-cache", "--install", "--tool", "godot"],
    ["--install", "--tool", "godot", "--install"],
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
        treeExists: (await stat(join(transactionRoot, "tree"))).isDirectory(),
      };
      throw new Error("partial stream");
    },
  };
  const setup = transportFrom({ status: 200, headers: {}, body: partialBody });

  await expectDownloadFailure(() => downloadPinnedArchive("godot", { cacheRoot, transport: setup.transport }), "network_rejected");
  assert.deepEqual(snapshot, { rootMode: 0o700, archiveExists: true, treeExists: true });
  assert.deepEqual(await readdir(join(cacheRoot, ".staging")), ["00000000-0000-4000-8000-000000000000"]);
});

test("single install publishes verified Godot and Blender fixture layouts", async (t) => {
  for (const [id, executableRelativePath] of [
    ["godot", "Godot_fixture"],
    ["blender", "fixture-blender/blender"],
  ]) {
    const cacheRoot = await temporaryCache(t);
    const contents = `fixture executable for ${id}\n`;
    const tool = fixtureTool(id, executableRelativePath, contents);
    const result = await installPinnedToolchain(id, {
      cacheRoot,
      tool,
      download: fixtureDownloader(Buffer.from(`synthetic ${id} archive`)),
      adapter: fixtureAdapter(executableRelativePath, contents),
      processRunner: fixtureProcessRunner(tool),
    });
    const destination = resolveCacheTarget(id, { cacheRoot });

    assert.deepEqual(result, {
      schemaVersion: 1,
      tool: id,
      state: "installed",
      network: "used",
      archive: {
        sizeBytes: Buffer.byteLength(`synthetic ${id} archive`),
        algorithm: "sha512",
        digest: createHash("sha512").update(`synthetic ${id} archive`).digest("hex"),
      },
      executable: {
        algorithm: "sha256",
        digest: tool.install.executableChecksum.value,
        version: tool.install.versionContract.mode === "exact_output"
          ? tool.install.versionContract.value
          : tool.install.versionContract.firstLine,
      },
    });
    assert.equal((await stat(join(destination, ...executableRelativePath.split("/")))).mode & 0o100, 0o100);
    assert.deepEqual(await readdir(join(cacheRoot, ".staging")), []);
  }
});

test("single install revalidates an existing executable offline without modifying it", async (t) => {
  const cacheRoot = await temporaryCache(t);
  const contents = "fixture executable\n";
  const tool = fixtureTool("godot", "Godot_fixture", contents);
  const destination = resolveCacheTarget("godot", { cacheRoot });
  const executablePath = join(destination, "Godot_fixture");
  await mkdir(destination, { recursive: true, mode: 0o700 });
  await writeFile(executablePath, contents);
  const originalMode = (await stat(executablePath)).mode & 0o777;
  let downloads = 0;
  let transportOpens = 0;

  const result = await installPinnedToolchain("godot", {
    cacheRoot,
    tool,
    download: async () => {
      downloads += 1;
      throw new Error("download must not run");
    },
    transport: { open: async () => { transportOpens += 1; } },
    processRunner: fixtureProcessRunner(tool),
  });

  assert.deepEqual(result, {
    schemaVersion: 1,
    tool: "godot",
    state: "existing_valid",
    network: "unused",
    executable: {
      algorithm: "sha256",
      digest: tool.install.executableChecksum.value,
      version: tool.install.versionContract.value,
    },
  });
  assert.equal(downloads, 0);
  assert.equal(transportOpens, 0);
  assert.equal((await stat(executablePath)).mode & 0o777, originalMode);
});

test("competing installers use one exclusive per-tool directory lock and one transport open", async (t) => {
  const cacheRoot = await temporaryCache(t);
  const contents = "fixture executable\n";
  const tool = fixtureTool("godot", "Godot_fixture", contents);
  let transportOpens = 0;
  let releaseDownload;
  let releaseSchedule;
  let signalDownloadOpen;
  let signalSchedule;
  const downloadOpened = new Promise((resolveDownloadOpen) => { signalDownloadOpen = resolveDownloadOpen; });
  const scheduleStarted = new Promise((resolveScheduleStarted) => { signalSchedule = resolveScheduleStarted; });
  const downloadMayFinish = new Promise((resolveDownload) => { releaseDownload = resolveDownload; });
  const scheduleMayFinish = new Promise((resolveSchedule) => { releaseSchedule = resolveSchedule; });
  const transport = {
    async open() {
      transportOpens += 1;
      signalDownloadOpen();
      await downloadMayFinish;
      return response(200);
    },
  };
  const download = async (_toolId, options) => {
    await options.transport.open("https://fixture.invalid/archive");
    return fixtureDownloader(Buffer.from("shared synthetic archive"))(_toolId, options);
  };
  let now = 0;
  const schedule = async (delayMilliseconds) => {
    signalSchedule();
    await scheduleMayFinish;
    now += delayMilliseconds;
  };
  const options = {
    cacheRoot,
    tool,
    transport,
    download,
    adapter: fixtureAdapter(tool.install.executableRelativePath, contents),
    processRunner: fixtureProcessRunner(tool),
    clock: () => now,
    schedule,
  };

  const first = installPinnedToolchain("godot", options);
  await downloadOpened;
  const lockDirectory = join(cacheRoot, ".locks", "godot");
  const metadata = JSON.parse(await readFile(join(lockDirectory, "metadata.json"), "utf8"));
  assert.deepEqual(Object.keys(metadata).sort(), ["createdAt", "token"]);
  assert.doesNotMatch(JSON.stringify(metadata), new RegExp(cacheRoot.replaceAll("/", "\\\\/"), "u"));

  const second = installPinnedToolchain("godot", options);
  await scheduleStarted;
  assert.equal(transportOpens, 1);
  releaseDownload();
  await first;
  releaseSchedule();
  const secondResult = await second;

  assert.equal(transportOpens, 1);
  assert.equal(secondResult.state, "existing_valid");
  await assert.rejects(stat(lockDirectory), { code: "ENOENT" });
});

test("an unknown stale lock times out by fake clock without downloading or deleting it", async (t) => {
  const cacheRoot = await temporaryCache(t);
  const contents = "fixture executable\n";
  const tool = fixtureTool("godot", "Godot_fixture", contents);
  const lockDirectory = join(cacheRoot, ".locks", "godot");
  await mkdir(lockDirectory, { recursive: true, mode: 0o700 });
  await writeFile(join(lockDirectory, "metadata.json"), JSON.stringify({ createdAt: "1970-01-01T00:00:00.000Z", owner: "unknown" }));
  let now = 0;
  let downloads = 0;
  const scheduleDelays = [];

  await expectDownloadFailure(
    () => installPinnedToolchain("godot", {
      cacheRoot,
      tool,
      download: async () => { downloads += 1; },
      clock: () => now,
      schedule: async (delayMilliseconds) => {
        scheduleDelays.push(delayMilliseconds);
        now += delayMilliseconds;
      },
    }),
    "lock_timeout",
  );

  assert.equal(downloads, 0);
  assert.deepEqual(scheduleDelays, Array(120).fill(250));
  assert.equal(await readFile(join(lockDirectory, "metadata.json"), "utf8"), JSON.stringify({ createdAt: "1970-01-01T00:00:00.000Z", owner: "unknown" }));
});

test("single install rejects a corrupt existing executable without downloading or overwriting it", async (t) => {
  const cacheRoot = await temporaryCache(t);
  const contents = "fixture executable\n";
  const tool = fixtureTool("godot", "Godot_fixture", contents);
  const destination = resolveCacheTarget("godot", { cacheRoot });
  const executablePath = join(destination, "Godot_fixture");
  await mkdir(destination, { recursive: true, mode: 0o700 });
  await writeFile(executablePath, "corrupt executable\n");
  let downloads = 0;

  await expectDownloadFailure(
    () => installPinnedToolchain("godot", {
      cacheRoot,
      tool,
      download: async () => {
        downloads += 1;
        throw new Error("download must not run");
      },
      processRunner: fixtureProcessRunner(tool),
    }),
    "install_invalid",
  );
  assert.equal(downloads, 0);
  assert.equal((await readFile(executablePath, "utf8")), "corrupt executable\n");
});

test("single install calls the adapter by argv and stdin while redacting its failure", async (t) => {
  const cacheRoot = await temporaryCache(t);
  const contents = "fixture executable\n";
  const tool = fixtureTool("godot", "Godot_fixture", contents);
  let invocation;

  await assert.rejects(
    () => installPinnedToolchain("godot", {
      cacheRoot,
      tool,
      download: fixtureDownloader(Buffer.from("synthetic archive")),
      processRunner: async (executable, argumentsList, input) => {
        invocation = { executable, argumentsList, request: JSON.parse(input) };
        return { code: 1, stdout: "", stderr: `archive rejected at ${join(cacheRoot, "host-path")}` };
      },
    }),
    (error) => {
      assert.equal(error.code, "adapter_failed");
      assert.match(error.message, /<REDACTED_PATH>/u);
      assert.doesNotMatch(error.message, new RegExp(cacheRoot.replaceAll("/", "\\/"), "u"));
      return true;
    },
  );
  assert.equal(invocation.executable, "python3");
  assert.deepEqual(invocation.argumentsList, [join(projectRoot, "scripts", "toolchain_archive.py")]);
  assert.equal(invocation.request.operation, "extract");
  assert.equal(invocation.request.format, "zip");
  assert.deepEqual(await readdir(join(cacheRoot, ".staging")), []);
});

test("single install rejects bad executables and destinations without leaking staging", async (t) => {
  const cacheRoot = await temporaryCache(t);
  const contents = "fixture executable\n";
  const tool = fixtureTool("godot", "Godot_fixture", contents);
  const sibling = join(cacheRoot, ".staging", "00000000-0000-4000-8000-000000000000");
  await mkdir(sibling, { recursive: true, mode: 0o700 });

  await expectDownloadFailure(
    () => installPinnedToolchain("godot", {
      cacheRoot,
      tool,
      download: fixtureDownloader(Buffer.from("digest mismatch")),
      adapter: fixtureAdapter(tool.install.executableRelativePath, "different executable\n"),
      processRunner: fixtureProcessRunner(tool),
    }),
    "executable_verification_failed",
  );
  await expectDownloadFailure(
    () => installPinnedToolchain("godot", {
      cacheRoot,
      tool,
      download: fixtureDownloader(Buffer.from("version mismatch")),
      adapter: fixtureAdapter(tool.install.executableRelativePath, contents),
      processRunner: async () => ({ code: 0, stdout: "not the locked version\n", stderr: "" }),
    }),
    "version_mismatch",
  );

  const destination = resolveCacheTarget("godot", { cacheRoot });
  await mkdir(destination, { recursive: true, mode: 0o700 });
  let downloads = 0;
  await expectDownloadFailure(
    () => installPinnedToolchain("godot", {
      cacheRoot,
      tool,
      download: async (...argumentsList) => {
        downloads += 1;
        return fixtureDownloader(Buffer.from("must not download"))(...argumentsList);
      },
    }),
    "install_invalid",
  );
  assert.equal(downloads, 0);
  await rm(destination, { recursive: true, force: true });

  await expectDownloadFailure(
    () => installPinnedToolchain("godot", {
      cacheRoot,
      tool,
      download: fixtureDownloader(Buffer.from("destination race")),
      adapter: async (request) => {
        await fixtureAdapter(tool.install.executableRelativePath, contents)(request);
        await mkdir(destination, { recursive: true, mode: 0o700 });
      },
      processRunner: fixtureProcessRunner(tool),
    }),
    "destination_exists",
  );
  assert.deepEqual(await readdir(join(cacheRoot, ".staging")), ["00000000-0000-4000-8000-000000000000"]);
});

test("bootstrap module uses only the built-in HTTPS transport", () => {
  const source = readFileSync(scriptPath, "utf8");
  assert.match(source, /node:https/u);
  assert.match(source, /node:child_process/u);
  assert.doesNotMatch(source, /node:http(?=["'])|node:(?:net|tls|dgram|dns)|\bfetch\s*\(/u);
  assert.doesNotMatch(source, /\bgit\b/u);
});
