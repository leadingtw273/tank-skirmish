import { spawnSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const artifactDirectory = join(projectRoot, "artifacts", "ci");
const toolCache =
  process.env.TANK_SKIRMISH_TOOL_CACHE ??
  join(process.env.XDG_CACHE_HOME ?? join(homedir(), ".cache"), "tank-skirmish", "toolchains");
const defaultGodot = join(
  toolCache,
  "godot",
  "4.7.1-stable",
  "Godot_v4.7.1-stable_linux.x86_64",
);
const godot = process.env.GODOT_BIN ?? defaultGodot;
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

function run(name, executable, argumentsList) {
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
  if (godotError.test(output)) {
    throw new Error(`${name} reported a Godot error`);
  }
}

run("version", godot, ["--version"]);
run("import", godot, ["--headless", "--path", ".", "--import"]);
run("smoke", godot, [
  "--headless",
  "--audio-driver",
  "Dummy",
  "--path",
  ".",
  "--script",
  "res://tests/smoke.gd",
]);

run("protected-project-diff", "git", ["diff", "--exit-code", "--", "project.godot"]);
console.log("Tank Skirmish quality gate passed.");
