import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { lstatSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { loadAndValidateToolchainLock } from "./validate-toolchain-lock.mjs";

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const artifactDirectory = join(projectRoot, "artifacts", "ci");
const lockPath = join(projectRoot, "docs", "toolchain-lock.json");
const toolchainLock = await loadAndValidateToolchainLock(lockPath);
const { resolveToolCacheRoot } = await import("./bootstrap-toolchain.mjs");
const godotTool = toolchainLock.tools.find((tool) => tool.id === "godot");
if (godotTool === undefined) {
  throw new Error("toolchain lock is missing Godot");
}
const godot = process.env.GODOT_BIN ?? join(
  resolveToolCacheRoot(),
  ...godotTool.install.cacheRelativePath.split("/"),
  ...godotTool.install.executableRelativePath.split("/"),
);
const godotDataRoot = join(projectRoot, ".godot", "xdg");
const environment = {
  ...process.env,
  XDG_DATA_HOME: process.env.XDG_DATA_HOME ?? join(godotDataRoot, "data"),
  XDG_CACHE_HOME: process.env.XDG_CACHE_HOME ?? join(godotDataRoot, "cache"),
  XDG_CONFIG_HOME: process.env.XDG_CONFIG_HOME ?? join(godotDataRoot, "config"),
};
const godotError = /(^|\s)(ERROR:|SCRIPT ERROR:)/u;

mkdirSync(artifactDirectory, { recursive: true });
mkdirSync(environment.XDG_DATA_HOME, { recursive: true });
mkdirSync(environment.XDG_CACHE_HOME, { recursive: true });
mkdirSync(environment.XDG_CONFIG_HOME, { recursive: true });

function run(name, executable, argumentsList, { scanGodotErrors = false } = {}) {
  const result = spawnSync(executable, argumentsList, {
    cwd: projectRoot,
    encoding: "utf8",
    env: environment,
  });
  const output = `${result.stdout ?? ""}${result.stderr ?? ""}`;
  writeFileSync(join(artifactDirectory, `${name}.log`), output, "utf8");
  process.stdout.write(output);

  if (result.error !== undefined) {
    throw new Error(`${name} could not start: ${result.error.message}`);
  }
  if (result.status !== 0) {
    throw new Error(`${name} exited with status ${String(result.status)}`);
  }
  if (scanGodotErrors && godotError.test(output)) {
    throw new Error(`${name} reported a Godot error`);
  }

  return output;
}

function assertRegularFile(path, description) {
  let stats;
  try {
    stats = lstatSync(path);
  } catch (error) {
    throw new Error(`${description} is missing: ${error.message}`);
  }

  if (!stats.isFile()) {
    throw new Error(`${description} must be a regular file: ${path}`);
  }
}

function assertVerifiedGodotExecutable(executablePath, tool) {
  assertRegularFile(executablePath, "Godot executable");
  const digest = createHash("sha256").update(readFileSync(executablePath)).digest("hex");
  if (digest !== tool.install.executableChecksum.value) {
    throw new Error(`Godot executable SHA-256 does not match toolchain lock: ${executablePath}`);
  }
}

function assertGodotVersionContract(output, tool) {
  const contract = tool.install.versionContract;
  if (contract.mode !== "exact_output") {
    throw new Error(`unsupported Godot version contract: ${contract.mode}`);
  }

  const normalizedOutput = output.replace(/\r\n/gu, "\n").replace(/\n$/u, "");
  if (normalizedOutput !== contract.value) {
    throw new Error("Godot version does not match toolchain lock");
  }
}

run("toolchain-lock-validation", process.execPath, ["scripts/validate-toolchain-lock.mjs", "--check"]);
run("toolchain-lock-tests", process.execPath, ["--test", "tests/toolchain-lock.test.mjs"]);
run("toolchain-archive-tests", "python3", ["tests/toolchain_archive_test.py"]);
run("toolchain-bootstrap-tests", process.execPath, ["--test", "tests/toolchain-bootstrap.test.mjs"]);
run("asset-lock-validation", process.execPath, ["scripts/validate-assets-lock.mjs", "--check"]);
run("asset-lock-tests", process.execPath, ["--test", "tests/assets-lock.test.mjs"]);
run("asset-conversion-staging-tests", process.execPath, ["--test", "tests/asset-conversion-staging.test.mjs"]);
run("asset-conversion-tests", process.execPath, ["--test", "tests/asset-conversion.test.mjs"]);

assertVerifiedGodotExecutable(godot, godotTool);

const visualReview = join(projectRoot, "scripts", "visual-review.mjs");
assertRegularFile(visualReview, "visual review entrypoint");
const { runStaticSelfCheck } = await import("./visual-review.mjs");
runStaticSelfCheck();

assertGodotVersionContract(run("version", godot, ["--version"], { scanGodotErrors: true }), godotTool);
run("import", godot, ["--headless", "--path", ".", "--import"], { scanGodotErrors: true });
run("smoke", godot, [
  "--headless",
  "--audio-driver",
  "Dummy",
  "--path",
  ".",
  "--script",
  "res://tests/smoke.gd",
], { scanGodotErrors: true });

run("protected-project-diff", "git", ["diff", "--exit-code", "--", "project.godot"]);
console.log("Tank Skirmish quality gate passed.");
