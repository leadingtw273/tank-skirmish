import { spawn } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { createReadStream, lstatSync, realpathSync, readFileSync, statSync } from "node:fs";
import { chmod, lstat, mkdir, open as openFile, rename, rm, stat } from "node:fs/promises";
import { request as httpsRequest } from "node:https";
import { homedir } from "node:os";
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

import { validateToolchainLock } from "./validate-toolchain-lock.mjs";

const moduleDirectory = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(moduleDirectory, "..");
const realProjectRoot = realpathSync(projectRoot);
const lockPath = join(projectRoot, "docs", "toolchain-lock.json");
const toolchainLock = validateToolchainLock(JSON.parse(readFileSync(lockPath, "utf8")));
const knownTools = new Set(toolchainLock.tools.map((tool) => tool.id));

export class ToolCacheResolutionError extends Error {
  constructor(code, detail) {
    super(detail === undefined ? code : `${code}: ${detail}`);
    this.name = "ToolCacheResolutionError";
    this.code = code;
  }
}

function fail(code, detail) {
  throw new ToolCacheResolutionError(code, detail);
}

function isSameOrInside(path, directory) {
  const pathRelativeToDirectory = relative(directory, path);
  return pathRelativeToDirectory === "" ||
    (!pathRelativeToDirectory.startsWith(`..${sep}`) && pathRelativeToDirectory !== "..");
}

function resolveViaExistingAncestor(path) {
  let ancestor = path;
  const prospectiveTail = [];

  while (true) {
    try {
      lstatSync(ancestor);
      break;
    } catch (error) {
      if (error?.code !== "ENOENT") {
        fail("io_error");
      }
    }
    const parent = dirname(ancestor);
    if (parent === ancestor) {
      fail("io_error");
    }
    prospectiveTail.unshift(basename(ancestor));
    ancestor = parent;
  }

  let realAncestor;
  try {
    realAncestor = realpathSync(ancestor);
  } catch {
    fail("io_error");
  }
  try {
    if (!statSync(realAncestor).isDirectory()) {
      fail("io_error");
    }
  } catch (error) {
    if (error instanceof ToolCacheResolutionError) {
      throw error;
    }
    fail("io_error");
  }
  return resolve(realAncestor, ...prospectiveTail);
}

function assertSafeCacheRoot(cacheRoot) {
  if (typeof cacheRoot !== "string" || !isAbsolute(cacheRoot)) {
    fail("invalid_cache_root");
  }

  const prospectiveRoot = resolveViaExistingAncestor(resolve(cacheRoot));
  if (isSameOrInside(prospectiveRoot, realProjectRoot)) {
    fail("repository_containment");
  }
  return prospectiveRoot;
}

function toolById(toolId) {
  if (!knownTools.has(toolId)) {
    fail("unknown_tool");
  }
  return toolchainLock.tools.find((tool) => tool.id === toolId);
}

function downloadFail(code) {
  throw new ToolCacheResolutionError(code);
}

function createHttpsTransport() {
  return {
    open(url) {
      return new Promise((resolveResponse, rejectResponse) => {
        const request = httpsRequest(url, (response) => {
          resolveResponse({
            status: response.statusCode,
            headers: response.headers,
            body: response,
          });
        });
        request.once("error", rejectResponse);
        request.end();
      });
    },
  };
}

function isAllowedGodotRedirect(location) {
  let destination;
  try {
    destination = new URL(location);
  } catch {
    return false;
  }
  return destination.protocol === "https:" &&
    destination.username === "" &&
    destination.password === "" &&
    destination.port === "" &&
    destination.hostname === "release-assets.githubusercontent.com" &&
    destination.pathname.startsWith("/github-production-release-asset/") &&
    destination.hash === "";
}

function isResponse(value) {
  return value !== null && typeof value === "object" &&
    Number.isInteger(value.status) && value.headers !== null && typeof value.headers === "object" &&
    value.body !== null && typeof value.body?.[Symbol.asyncIterator] === "function";
}

async function openResponse(transport, url) {
  try {
    const response = await transport.open(url);
    if (!isResponse(response)) {
      downloadFail("network_rejected");
    }
    return response;
  } catch (error) {
    if (error instanceof ToolCacheResolutionError) {
      throw error;
    }
    downloadFail("network_rejected");
  }
}

async function openPinnedArchive(transport, tool) {
  const firstResponse = await openResponse(transport, tool.archive.url);
  if (firstResponse.status === 200) {
    return firstResponse;
  }

  if (tool.id !== "godot" || !new Set([302, 303, 307, 308]).has(firstResponse.status)) {
    downloadFail("network_rejected");
  }

  const location = firstResponse.headers.location;
  if (typeof location !== "string" || !isAllowedGodotRedirect(location)) {
    downloadFail("network_rejected");
  }

  const secondResponse = await openResponse(transport, location);
  if (secondResponse.status !== 200) {
    downloadFail("network_rejected");
  }
  return secondResponse;
}

async function streamAndVerifyArchive(body, archivePath, archive) {
  let archiveFile;
  try {
    archiveFile = await openFile(archivePath, "wx", 0o600);
  } catch {
    downloadFail("io_error");
  }

  const hash = createHash(archive.checksum.algorithm);
  let size = 0;
  try {
    for await (const chunk of body) {
      if (!(chunk instanceof Uint8Array)) {
        downloadFail("network_rejected");
      }
      size += chunk.byteLength;
      if (!Number.isSafeInteger(size) || size > archive.sizeBytes) {
        downloadFail("verification_failed");
      }
      hash.update(chunk);
      try {
        await archiveFile.write(chunk);
      } catch {
        downloadFail("io_error");
      }
    }
  } catch (error) {
    if (error instanceof ToolCacheResolutionError) {
      throw error;
    }
    downloadFail("network_rejected");
  } finally {
    try {
      await archiveFile.close();
    } catch (error) {
      if (!(error instanceof ToolCacheResolutionError)) {
        downloadFail("io_error");
      }
    }
  }

  const digest = hash.digest("hex");
  if (size !== archive.sizeBytes || digest !== archive.checksum.value) {
    downloadFail("verification_failed");
  }
  return { sizeBytes: size, algorithm: archive.checksum.algorithm, digest };
}

export async function downloadPinnedArchive(
  toolId,
  { cacheRoot = resolveToolCacheRoot(), transport = createHttpsTransport() } = {},
) {
  const tool = toolById(toolId);
  const safeCacheRoot = assertSafeCacheRoot(cacheRoot);
  const stagingRoot = join(safeCacheRoot, ".staging", randomUUID());
  const downloadDirectory = join(stagingRoot, "download");
  const archivePath = join(downloadDirectory, "archive");
  const treePath = join(stagingRoot, "tree");

  try {
    await mkdir(downloadDirectory, { recursive: true, mode: 0o700 });
    await chmod(stagingRoot, 0o700);
    await mkdir(treePath, { mode: 0o700 });
    const response = await openPinnedArchive(transport, tool);
    const archive = await streamAndVerifyArchive(response.body, archivePath, tool.archive);
    return { archivePath, treePath, archive };
  } catch (error) {
    try {
      await rm(stagingRoot, { recursive: true, force: true });
    } catch {
      downloadFail("io_error");
    }
    if (error instanceof ToolCacheResolutionError) {
      throw error;
    }
    downloadFail("io_error");
  }
}

function sanitizeAdapterError(value) {
  return value.replace(/(?:[A-Za-z]:[\\/]|\/)[^\s"'`<>{}\[\]]*/gu, "<REDACTED_PATH>");
}

function runProcess(executable, argumentsList, input) {
  return new Promise((resolveResult) => {
    let child;
    try {
      child = spawn(executable, argumentsList, { stdio: ["pipe", "pipe", "pipe"] });
    } catch {
      resolveResult({ code: null, stdout: "", stderr: "" });
      return;
    }

    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.once("error", () => resolveResult({ code: null, stdout, stderr }));
    child.once("close", (code) => resolveResult({ code, stdout, stderr }));
    child.stdin.end(input);
  });
}

async function runArchiveAdapter({ archivePath, treePath, archive }, { processRunner = runProcess } = {}) {
  const request = JSON.stringify({
    operation: "extract",
    archivePath,
    format: archive.format,
    contract: {
      memberCount: archive.memberCount,
      topLevelDirectory: archive.topLevelDirectory,
      exactMemberNames: archive.exactMemberNames,
      allowedEntryTypes: archive.allowedEntryTypes,
    },
    stagingRoot: treePath,
  });
  const result = await processRunner("python3", [join(moduleDirectory, "toolchain_archive.py")], request);
  if (result.code !== 0) {
    fail("adapter_failed", sanitizeAdapterError(result.stderr || result.stdout || "adapter_rejected"));
  }

  try {
    const summary = JSON.parse(result.stdout);
    if (summary?.ok !== true) {
      fail("adapter_failed", "adapter_rejected");
    }
  } catch (error) {
    if (error instanceof ToolCacheResolutionError) throw error;
    fail("adapter_failed", "adapter_rejected");
  }
}

async function assertDestinationMissing(destination) {
  try {
    await lstat(destination);
  } catch (error) {
    if (error?.code === "ENOENT") return;
    fail("io_error");
  }
  fail("destination_exists");
}

function transactionRootFrom({ archivePath, treePath }, cacheRoot) {
  const stagingRoot = dirname(treePath);
  if (
    basename(treePath) !== "tree" ||
    basename(archivePath) !== "archive" ||
    dirname(archivePath) !== join(stagingRoot, "download") ||
    dirname(stagingRoot) !== join(cacheRoot, ".staging") ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/u.test(basename(stagingRoot))
  ) {
    fail("staging_invalid");
  }
  return stagingRoot;
}

function resolveExecutablePath(treePath, executableRelativePath) {
  const executablePath = resolve(treePath, ...executableRelativePath.split("/"));
  if (!isSameOrInside(executablePath, treePath)) {
    fail("executable_invalid");
  }
  return executablePath;
}

async function verifyExecutable(executablePath, tool, processRunner = runProcess) {
  let metadata;
  try {
    metadata = await lstat(executablePath);
  } catch {
    fail("executable_invalid");
  }
  if (!metadata.isFile()) fail("executable_invalid");

  try {
    await chmod(executablePath, (metadata.mode & 0o777) | 0o100);
    metadata = await lstat(executablePath);
  } catch {
    fail("io_error");
  }
  if (!metadata.isFile() || (metadata.mode & 0o100) === 0) fail("executable_invalid");

  const hash = createHash("sha256");
  try {
    for await (const chunk of createReadStream(executablePath)) {
      hash.update(chunk);
    }
  } catch {
    fail("io_error");
  }
  const digest = hash.digest("hex");
  if (digest !== tool.install.executableChecksum.value) fail("executable_verification_failed");

  const result = await processRunner(executablePath, ["--version"], "");
  if (result.code !== 0) fail("version_mismatch");
  const lines = result.stdout.replace(/\r\n/gu, "\n").split("\n");
  const contract = tool.install.versionContract;
  if (contract.mode === "exact_output") {
    const output = result.stdout.replace(/\r\n/gu, "\n").replace(/\n$/u, "");
    if (output !== contract.value) fail("version_mismatch");
    return { algorithm: "sha256", digest, version: output };
  }
  if (
    lines[0] !== contract.firstLine ||
    !lines.some((line) => line.trim() === `build hash: ${contract.buildHash}`)
  ) {
    fail("version_mismatch");
  }
  return { algorithm: "sha256", digest, version: lines[0] };
}

async function publishTree(treePath, destination) {
  const destinationParent = dirname(destination);
  try {
    await mkdir(destinationParent, { recursive: true, mode: 0o700 });
    const [treeMetadata, destinationParentMetadata] = await Promise.all([
      stat(treePath),
      stat(destinationParent),
    ]);
    if (treeMetadata.dev !== destinationParentMetadata.dev) fail("cross_filesystem");
    await assertDestinationMissing(destination);
    await rename(treePath, destination);
  } catch (error) {
    if (error instanceof ToolCacheResolutionError) throw error;
    if (error?.code === "EXDEV") fail("cross_filesystem");
    if (new Set(["EEXIST", "ENOTEMPTY", "ENOTDIR"]).has(error?.code)) fail("destination_exists");
    fail("publish_failed");
  }
}

export async function installPinnedToolchain(
  toolId,
  {
    cacheRoot = resolveToolCacheRoot(),
    transport = createHttpsTransport(),
    download = downloadPinnedArchive,
    adapter = runArchiveAdapter,
    processRunner = runProcess,
    tool = toolById(toolId),
  } = {},
) {
  const safeCacheRoot = assertSafeCacheRoot(cacheRoot);
  const destination = resolveCacheTarget(toolId, { cacheRoot: safeCacheRoot });
  let stagingRoot;

  await assertDestinationMissing(destination);
  try {
    const staged = await download(toolId, { cacheRoot: safeCacheRoot, transport });
    stagingRoot = transactionRootFrom(staged, safeCacheRoot);
    await adapter(
      { archivePath: staged.archivePath, treePath: staged.treePath, archive: tool.archive },
      { processRunner },
    );
    const executable = await verifyExecutable(
      resolveExecutablePath(staged.treePath, tool.install.executableRelativePath),
      tool,
      processRunner,
    );
    await publishTree(staged.treePath, destination);
    return {
      schemaVersion: 1,
      tool: toolId,
      state: "installed",
      network: "used",
      archive: staged.archive,
      executable,
    };
  } finally {
    if (stagingRoot !== undefined) {
      try {
        await rm(stagingRoot, { recursive: true, force: true });
      } catch {
        fail("io_error");
      }
    }
  }
}

export function resolveToolCacheRoot(environment = process.env) {
  const cacheHome = environment.XDG_CACHE_HOME || join(homedir(), ".cache");
  const cacheRoot = environment.TANK_SKIRMISH_TOOL_CACHE ?? join(cacheHome, "tank-skirmish", "toolchains");
  return assertSafeCacheRoot(cacheRoot);
}

export function resolveCacheTarget(toolId, { cacheRoot = resolveToolCacheRoot() } = {}) {
  const tool = toolById(toolId);
  const safeCacheRoot = assertSafeCacheRoot(cacheRoot);
  const target = resolve(safeCacheRoot, tool.install.cacheRelativePath);
  if (!isSameOrInside(target, safeCacheRoot)) {
    fail("repository_containment");
  }
  return target;
}

function writeJsonLine(stream, value) {
  stream.write(`${JSON.stringify(value)}\n`);
}

function parseArguments(args) {
  let checkCache = false;
  let tool;
  let cacheDir;

  for (let index = 0; index < args.length; index += 1) {
    const argument = args[index];
    if (argument === "--check-cache") {
      if (checkCache) return null;
      checkCache = true;
      continue;
    }
    if (argument === "--tool" || argument === "--cache-dir") {
      const value = args[index + 1];
      if (value === undefined || value.startsWith("--")) return null;
      if (argument === "--tool") {
        if (tool !== undefined) return null;
        tool = value;
      } else {
        if (cacheDir !== undefined) return null;
        cacheDir = value;
      }
      index += 1;
      continue;
    }
    return null;
  }

  if (!checkCache || !knownTools.has(tool) || (cacheDir !== undefined && !isAbsolute(cacheDir))) {
    return null;
  }
  return { tool, cacheDir };
}

export function runBootstrapToolchainCli(args, { stdout, stderr, environment = process.env }) {
  const parsed = parseArguments(args);
  if (parsed === null) {
    writeJsonLine(stderr, { ok: false, code: "usage_error" });
    return 2;
  }

  try {
    const cacheRoot = parsed.cacheDir ?? resolveToolCacheRoot(environment);
    resolveCacheTarget(parsed.tool, { cacheRoot });
    writeJsonLine(stdout, {
      tool: parsed.tool,
      mode: "check_cache",
      state: "cache_target_valid",
      network: "unused",
    });
    return 0;
  } catch (error) {
    if (error instanceof ToolCacheResolutionError) {
      writeJsonLine(stderr, { ok: false, code: "cache_target_error" });
      return 3;
    }
    throw error;
  }
}

const scriptPath = fileURLToPath(import.meta.url);
if (process.argv[1] !== undefined && resolve(process.argv[1]) === scriptPath) {
  process.exitCode = runBootstrapToolchainCli(process.argv.slice(2), {
    stdout: process.stdout,
    stderr: process.stderr,
  });
}
