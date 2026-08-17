import { createHash, randomUUID } from "node:crypto";
import { lstatSync, realpathSync, readFileSync, statSync } from "node:fs";
import { chmod, mkdir, open as openFile, rm } from "node:fs/promises";
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
  constructor(code) {
    super(code);
    this.name = "ToolCacheResolutionError";
    this.code = code;
  }
}

function fail(code) {
  throw new ToolCacheResolutionError(code);
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

  if (size !== archive.sizeBytes || hash.digest("hex") !== archive.checksum.value) {
    downloadFail("verification_failed");
  }
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
  const treePath = join(downloadDirectory, "tree");

  try {
    await mkdir(downloadDirectory, { recursive: true, mode: 0o700 });
    await chmod(stagingRoot, 0o700);
    await mkdir(treePath, { mode: 0o700 });
    const response = await openPinnedArchive(transport, tool);
    await streamAndVerifyArchive(response.body, archivePath, tool.archive);
    return { archivePath, treePath };
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
