import { lstatSync, realpathSync, readFileSync, statSync } from "node:fs";
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
