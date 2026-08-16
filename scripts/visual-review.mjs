import { spawnSync } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import {
  lstatSync,
  mkdirSync,
  readFileSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { homedir, platform } from "node:os";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { inflateSync } from "node:zlib";

const scriptPath = fileURLToPath(import.meta.url);
const projectRoot = resolve(dirname(scriptPath), "..");
const defaultScene = "res://src/main.tscn";
const probeScene = "res://tests/fixtures/visual_probe.tscn";
const viewportWidth = 1920;
const viewportHeight = 1080;
const acceptanceCriterion =
  "WSLg 自動產出的正式證據為 1920×1080 非空白 PNG，且 visual-manifest.json 的尺寸與 SHA-256 可驗證。";
const toolCache =
  process.env.TANK_SKIRMISH_TOOL_CACHE ??
  join(process.env.XDG_CACHE_HOME ?? join(homedir(), ".cache"), "tank-skirmish", "toolchains");
const defaultGodot = join(
  toolCache,
  "godot",
  "4.7.1-stable",
  "Godot_v4.7.1-stable_linux.x86_64",
);

function fail(message) {
  throw new Error(`Visual review failed closed: ${message}`);
}

function required(value, message) {
  if (!value) {
    fail(message);
  }
  return value;
}

function parseArguments(argumentsList) {
  const options = { scene: defaultScene, selfCheck: false };
  for (const argument of argumentsList) {
    if (argument === "--self-check") {
      options.selfCheck = true;
    } else if (argument.startsWith("--out=")) {
      options.out = argument.slice("--out=".length);
    } else if (argument.startsWith("--scene=")) {
      options.scene = argument.slice("--scene=".length);
    } else {
      fail(`unsupported argument: ${argument}`);
    }
  }
  return options;
}

function assertSelfCheck() {
  const scriptStat = lstatSync(scriptPath);
  required(scriptStat.isFile(), "scripts/visual-review.mjs is not a regular file");
  const probeScenePath = join(projectRoot, "tests", "fixtures", "visual_probe.tscn");
  const probeScriptPath = join(projectRoot, "tests", "fixtures", "visual_probe.gd");
  const probeUidPath = join(projectRoot, "tests", "fixtures", "visual_probe.gd.uid");
  required(lstatSync(probeScenePath).isFile(), "visual probe scene is not a regular file");
  required(lstatSync(probeScriptPath).isFile(), "visual probe script is not a regular file");
  required(lstatSync(probeUidPath).isFile(), "visual probe UID is not a regular file");
  const source = readFileSync(scriptPath, "utf8");
  for (const marker of [
    "--self-check",
    defaultScene,
    "visual-manifest.json",
    "verifyPngPixels",
    "deviceScaleFactor",
    acceptanceCriterion,
  ]) {
    required(source.includes(marker), `static contract marker is missing: ${marker}`);
  }
  const probeSource = readFileSync(probeScriptPath, "utf8");
  for (const marker of ["--target-scene=", "--capture-out=", "get_image()", "save_png"]) {
    required(probeSource.includes(marker), `probe contract marker is missing: ${marker}`);
  }
  required(/^uid:\/\/\w+$/u.test(readFileSync(probeUidPath, "utf8").trim()), "visual probe UID is invalid");
  console.log("Visual review static self-check passed.");
}

function ensureRepoOutputDirectory(value) {
  required(value, "--out=<absolute directory> is required");
  required(isAbsolute(value), "--out must be an absolute directory");
  const outputDirectory = resolve(value);
  const repoRelative = relative(projectRoot, outputDirectory);
  required(
    repoRelative !== "" && !repoRelative.startsWith(`..${sep}`) && repoRelative !== "..",
    "--out must be inside this repository so the artifact path is repo-relative",
  );
  return { outputDirectory, repoRelative };
}

function resolveScene(scene) {
  required(scene.startsWith("res://"), "--scene must use a res:// path");
  required(scene.endsWith(".tscn"), "--scene must identify a .tscn scene");
  const relativeScenePath = scene.slice("res://".length);
  const absoluteScenePath = resolve(projectRoot, relativeScenePath);
  required(
    absoluteScenePath.startsWith(`${projectRoot}${sep}`),
    "--scene escapes the repository",
  );
  required(statSync(absoluteScenePath).isFile(), `scene is missing: ${scene}`);
  return scene;
}

function displayEnvironment() {
  if (platform() !== "linux") {
    fail(`Linux runner is required, received ${platform()}`);
  }
  const display = process.env.WAYLAND_DISPLAY ?? process.env.DISPLAY;
  required(display, "no WSLg/display is available (DISPLAY and WAYLAND_DISPLAY are unset)");
  const isWslg = Boolean(process.env.WSL_INTEROP) || Boolean(process.env.WSL_DISTRO_NAME);
  return {
    platform: "linux",
    environment: isWslg ? "WSLg" : "linux-graphical",
    displayServer: process.env.WAYLAND_DISPLAY ? "wayland" : "x11",
  };
}

function runGodot(godot, scene, capturePath) {
  const result = spawnSync(
    godot,
    [
      "--path",
      projectRoot,
      "--rendering-method",
      "gl_compatibility",
      "--resolution",
      `${viewportWidth}x${viewportHeight}`,
      "--scene",
      probeScene,
      "--",
      `--target-scene=${scene}`,
      `--capture-out=${capturePath}`,
    ],
    { cwd: projectRoot, encoding: "utf8", env: process.env },
  );
  const output = `${result.stdout ?? ""}${result.stderr ?? ""}`;
  process.stdout.write(output);
  if (result.error) {
    fail(`Godot renderer could not start: ${result.error.message}`);
  }
  if (result.status !== 0) {
    fail(`Godot renderer exited with status ${String(result.status)}`);
  }
  if (/(^|\s)(ERROR:|SCRIPT ERROR:)/u.test(output)) {
    fail("Godot renderer reported an engine or script error");
  }
}

function pngChunks(buffer) {
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  required(buffer.subarray(0, 8).equals(signature), "capture is not a PNG");
  const chunks = [];
  let offset = 8;
  while (offset < buffer.length) {
    required(offset + 12 <= buffer.length, "PNG chunk is truncated");
    const length = buffer.readUInt32BE(offset);
    const type = buffer.toString("ascii", offset + 4, offset + 8);
    const start = offset + 8;
    const end = start + length;
    required(end + 4 <= buffer.length, `PNG ${type} chunk is truncated`);
    chunks.push({ type, data: buffer.subarray(start, end) });
    offset = end + 4;
    if (type === "IEND") {
      break;
    }
  }
  required(chunks.at(-1)?.type === "IEND", "PNG has no IEND chunk");
  return chunks;
}

function paeth(left, up, upLeft) {
  const estimate = left + up - upLeft;
  const leftDistance = Math.abs(estimate - left);
  const upDistance = Math.abs(estimate - up);
  const upLeftDistance = Math.abs(estimate - upLeft);
  if (leftDistance <= upDistance && leftDistance <= upLeftDistance) return left;
  return upDistance <= upLeftDistance ? up : upLeft;
}

function verifyPngPixels(pngPath) {
  const chunks = pngChunks(readFileSync(pngPath));
  const header = chunks.find((chunk) => chunk.type === "IHDR")?.data;
  required(header?.length === 13, "PNG has no valid IHDR chunk");
  const width = header.readUInt32BE(0);
  const height = header.readUInt32BE(4);
  const bitDepth = header[8];
  const colorType = header[9];
  const interlace = header[12];
  required(width === viewportWidth && height === viewportHeight, `PNG is ${width}×${height}, expected 1920×1080`);
  required(bitDepth === 8, `unsupported PNG bit depth: ${String(bitDepth)}`);
  required(interlace === 0, "interlaced PNG captures are not supported");
  const channels = { 0: 1, 2: 3, 4: 2, 6: 4 }[colorType];
  required(channels, `unsupported PNG color type: ${String(colorType)}`);
  const compressed = Buffer.concat(chunks.filter((chunk) => chunk.type === "IDAT").map((chunk) => chunk.data));
  required(compressed.length > 0, "PNG has no image data");
  const data = inflateSync(compressed);
  const rowBytes = width * channels;
  required(data.length === height * (rowBytes + 1), "PNG pixel data has an unexpected length");

  let previous = Buffer.alloc(rowBytes);
  let offset = 0;
  let firstPixel;
  let hasVisiblePixel = false;
  let hasNonBlackPixel = false;
  let hasDifferentPixel = false;
  for (let row = 0; row < height; row += 1) {
    const filter = data[offset];
    offset += 1;
    const filtered = data.subarray(offset, offset + rowBytes);
    offset += rowBytes;
    const unfiltered = Buffer.alloc(rowBytes);
    for (let index = 0; index < rowBytes; index += 1) {
      const left = index >= channels ? unfiltered[index - channels] : 0;
      const up = previous[index];
      const upLeft = index >= channels ? previous[index - channels] : 0;
      const value = filtered[index];
      if (filter === 0) unfiltered[index] = value;
      else if (filter === 1) unfiltered[index] = (value + left) & 255;
      else if (filter === 2) unfiltered[index] = (value + up) & 255;
      else if (filter === 3) unfiltered[index] = (value + Math.floor((left + up) / 2)) & 255;
      else if (filter === 4) unfiltered[index] = (value + paeth(left, up, upLeft)) & 255;
      else fail(`PNG uses an unknown filter: ${String(filter)}`);
    }
    for (let index = 0; index < rowBytes; index += channels) {
      const red = unfiltered[index];
      const green = colorType === 0 || colorType === 4 ? red : unfiltered[index + 1];
      const blue = colorType === 0 || colorType === 4 ? red : unfiltered[index + 2];
      const alpha = colorType === 4 ? unfiltered[index + 1] : colorType === 6 ? unfiltered[index + 3] : 255;
      const pixel = `${red},${green},${blue},${alpha}`;
      if (firstPixel === undefined) firstPixel = pixel;
      else if (pixel !== firstPixel) hasDifferentPixel = true;
      if (alpha !== 0) hasVisiblePixel = true;
      if (alpha !== 0 && (red !== 0 || green !== 0 || blue !== 0)) hasNonBlackPixel = true;
    }
    previous = unfiltered;
  }
  required(hasVisiblePixel, "PNG is fully transparent");
  required(hasNonBlackPixel, "PNG is fully black");
  required(hasDifferentPixel, "PNG is a single-color blank image");
  return { width, height, nonBlank: true };
}

function commandOutput(command, argumentsList, label) {
  const result = spawnSync(command, argumentsList, { cwd: projectRoot, encoding: "utf8" });
  if (result.error || result.status !== 0) {
    fail(`${label} could not run`);
  }
  return result.stdout.trim();
}

function main() {
  const options = parseArguments(process.argv.slice(2));
  if (options.selfCheck) {
    required(process.argv.length === 3, "--self-check cannot be combined with runtime options");
    assertSelfCheck();
    return;
  }
  assertSelfCheck();
  const { outputDirectory, repoRelative } = ensureRepoOutputDirectory(options.out);
  mkdirSync(outputDirectory, { recursive: true });
  const pngName = "visual-evidence.png";
  const pngPath = join(outputDirectory, pngName);
  const manifestPath = join(outputDirectory, "visual-manifest.json");
  rmSync(manifestPath, { force: true });
  rmSync(pngPath, { force: true });
  const scene = resolveScene(options.scene);
  const runner = displayEnvironment();
  const godot = process.env.GODOT_BIN ?? defaultGodot;
  const version = commandOutput(godot, ["--version"], "Godot version check");
  required(/^4\.7\.1\.stable/u.test(version), `Godot 4.7.1-stable is required, received ${version}`);

  const pendingPngPath = join(outputDirectory, `.visual-evidence-${randomUUID()}.pending.png`);
  try {
    runGodot(godot, scene, pendingPngPath);
    required(statSync(pendingPngPath).isFile(), "Godot completed without producing a PNG capture");
    const image = verifyPngPixels(pendingPngPath);
    renameSync(pendingPngPath, pngPath);
    const artifactPath = join(repoRelative, pngName).split(sep).join("/");
    const manifest = {
      schemaVersion: 1,
      title: "Tank Skirmish visual evidence preflight",
      acceptanceCriterion,
      gitHead: commandOutput("git", ["rev-parse", "HEAD"], "Git head lookup"),
      godotVersion: version,
      runner,
      viewport: { width: viewportWidth, height: viewportHeight },
      deviceScaleFactor: 1,
      artifact: {
        repoRelativePath: artifactPath,
        mediaType: "image/png",
        sha256: createHash("sha256").update(readFileSync(pngPath)).digest("hex"),
      },
      scene,
      verification: image,
    };
    writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
    console.log(`Visual review evidence written to ${artifactPath}`);
  } catch (error) {
    rmSync(pendingPngPath, { force: true });
    rmSync(manifestPath, { force: true });
    rmSync(pngPath, { force: true });
    throw error;
  }
}

try {
  main();
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}
