import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  existsSync,
  lstatSync,
  mkdirSync,
  readFileSync,
  realpathSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { inflateSync } from "node:zlib";

const CONTRACT_VERSION = "visual-review-v1";
const REQUIRED_WIDTH = 1920;
const REQUIRED_HEIGHT = 1080;
const DEFAULT_SCENE = "res://src/main.tscn";
const PROBE_SCENE_PREFIX = "res://tests/fixtures/";
const ARTIFACT_NAME = "visual-evidence.png";
const MANIFEST_NAME = "visual-manifest.json";
const STANDARD_ACCEPTANCE =
  "WSLg 自動產出的正式證據為 1920×1080 非空白 PNG，且 visual-manifest.json 的尺寸與 SHA-256 可驗證。";
const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
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

function fail(message) {
  throw new Error(message);
}

function assertRegularFile(path, description) {
  let stats;
  try {
    stats = lstatSync(path);
  } catch (error) {
    fail(`${description} is missing: ${error.message}`);
  }
  if (!stats.isFile()) {
    fail(`${description} must be a regular file: ${path}`);
  }
}

function parseArguments(argumentsList) {
  const options = { out: null, scene: DEFAULT_SCENE, selfCheck: false };
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

  if (options.selfCheck && argumentsList.length !== 1) {
    fail("--self-check cannot be combined with other arguments");
  }
  return options;
}

export function runStaticSelfCheck() {
  assertRegularFile(fileURLToPath(import.meta.url), "visual review entrypoint");
  const source = readFileSync(fileURLToPath(import.meta.url), "utf8");
  const probeScenePath = join(projectRoot, "tests", "fixtures", "visual_probe.tscn");
  const probeScriptPath = join(projectRoot, "tests", "fixtures", "visual_probe.gd");
  assertRegularFile(probeScenePath, "visual probe scene");
  assertRegularFile(probeScriptPath, "visual probe script");

  const probeScene = readFileSync(probeScenePath, "utf8");
  const probeScript = readFileSync(probeScriptPath, "utf8");
  const requiredEntrypointMarkers = [
    `const CONTRACT_VERSION = "${CONTRACT_VERSION}";`,
    "function inspectPng",
    "function validateOutputDirectory",
    "--self-check",
    "visual-manifest.json",
  ];
  for (const marker of requiredEntrypointMarkers) {
    if (!source.includes(marker)) {
      fail(`visual review contract marker is missing: ${marker}`);
    }
  }
  if (!probeScene.includes('path="res://tests/fixtures/visual_probe.gd"')) {
    fail("visual probe scene does not reference its fixture script");
  }
  for (const marker of ["get_viewport().get_texture().get_image()", "save_png"]) {
    if (!probeScript.includes(marker)) {
      fail(`visual probe capture marker is missing: ${marker}`);
    }
  }

  console.log(`${CONTRACT_VERSION} static self-check passed.`);
}

function requireSupportedGodot() {
  const result = spawnSync(godot, ["--version"], {
    cwd: projectRoot,
    encoding: "utf8",
    env: environment,
  });
  if (result.error !== undefined) {
    fail(`Godot could not start: ${result.error.message}`);
  }
  if (result.status !== 0) {
    fail(`Godot version check exited with status ${String(result.status)}`);
  }
  const version = `${result.stdout ?? ""}${result.stderr ?? ""}`.trim();
  if (!/^4\.7\.1(?:[.-]stable)/u.test(version)) {
    fail(`Godot 4.7.1-stable is required; found ${version || "no version output"}`);
  }
  return version;
}

function detectRunner() {
  if (process.platform !== "linux") {
    fail(`a Linux graphical runner is required; found ${process.platform}`);
  }
  if (!process.env.DISPLAY && !process.env.WAYLAND_DISPLAY) {
    fail("no WSLg/X11/Wayland display is available; refusing headless capture");
  }
  const wslg = existsSync("/mnt/wslg");
  return wslg ? "Linux/WSLg" : "Linux graphical";
}

function validateOutputDirectory(output) {
  if (!output || !isAbsolute(output)) {
    fail("--out must be an absolute directory inside this repository");
  }
  const outputDirectory = resolve(output);
  const relativeOutput = relative(projectRoot, outputDirectory);
  if (relativeOutput === "" || relativeOutput === ".." || relativeOutput.startsWith(`..${sep}`)) {
    fail("--out must be a subdirectory of the repository so the artifact path is repo-relative");
  }
  return outputDirectory;
}

function resolveContainedOutputDirectory(outputDirectory) {
  mkdirSync(outputDirectory, { recursive: true });
  const resolvedProjectRoot = realpathSync(projectRoot);
  const resolvedOutputDirectory = realpathSync(outputDirectory);
  const relativeOutput = relative(resolvedProjectRoot, resolvedOutputDirectory);
  if (relativeOutput === "" || relativeOutput === ".." || relativeOutput.startsWith(`..${sep}`)) {
    fail("--out resolves outside the repository");
  }
  return { resolvedProjectRoot, resolvedOutputDirectory };
}

function validateScene(scene) {
  if (!scene.startsWith("res://") || scene.includes("..") || !scene.endsWith(".tscn")) {
    fail(`--scene must be a project-local .tscn resource: ${scene}`);
  }
  if (scene !== DEFAULT_SCENE && !scene.startsWith(PROBE_SCENE_PREFIX)) {
    fail(`--scene is limited to ${DEFAULT_SCENE} or isolated test fixtures`);
  }
  const scenePath = resolve(projectRoot, scene.slice("res://".length));
  const sceneRelativePath = relative(projectRoot, scenePath);
  if (sceneRelativePath === ".." || sceneRelativePath.startsWith(`..${sep}`)) {
    fail(`--scene resolves outside the repository: ${scene}`);
  }
  assertRegularFile(scenePath, "requested scene");
}

function paeth(left, above, upperLeft) {
  const prediction = left + above - upperLeft;
  const leftDistance = Math.abs(prediction - left);
  const aboveDistance = Math.abs(prediction - above);
  const upperLeftDistance = Math.abs(prediction - upperLeft);
  if (leftDistance <= aboveDistance && leftDistance <= upperLeftDistance) {
    return left;
  }
  return aboveDistance <= upperLeftDistance ? above : upperLeft;
}

function inspectPng(path) {
  const png = readFileSync(path);
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  if (png.length < signature.length || !png.subarray(0, signature.length).equals(signature)) {
    fail("capture is not a PNG file");
  }

  let cursor = signature.length;
  let width = 0;
  let height = 0;
  let bitDepth = 0;
  let colorType = 0;
  const compressedParts = [];
  while (cursor + 12 <= png.length) {
    const length = png.readUInt32BE(cursor);
    const type = png.subarray(cursor + 4, cursor + 8).toString("ascii");
    const dataStart = cursor + 8;
    const dataEnd = dataStart + length;
    if (dataEnd + 4 > png.length) {
      fail(`PNG ${type} chunk is truncated`);
    }
    const data = png.subarray(dataStart, dataEnd);
    if (type === "IHDR") {
      if (length !== 13) {
        fail("PNG IHDR has an invalid length");
      }
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      bitDepth = data[8];
      colorType = data[9];
      if (data[10] !== 0 || data[11] !== 0 || data[12] !== 0) {
        fail("PNG must use non-interlaced standard compression and filtering");
      }
    } else if (type === "IDAT") {
      compressedParts.push(data);
    } else if (type === "IEND") {
      break;
    }
    cursor = dataEnd + 4;
  }

  if (width !== REQUIRED_WIDTH || height !== REQUIRED_HEIGHT) {
    fail(`capture dimensions must be ${REQUIRED_WIDTH}x${REQUIRED_HEIGHT}; found ${width}x${height}`);
  }
  if (bitDepth !== 8 || ![2, 6].includes(colorType) || compressedParts.length === 0) {
    fail("PNG must be an 8-bit RGB or RGBA image with pixel data");
  }

  const channels = colorType === 6 ? 4 : 3;
  const bytesPerPixel = channels;
  const rowLength = width * bytesPerPixel;
  const pixelData = inflateSync(Buffer.concat(compressedParts));
  if (pixelData.length !== height * (rowLength + 1)) {
    fail("PNG pixel data has an unexpected length");
  }

  let sourceOffset = 0;
  let previousRow = Buffer.alloc(rowLength);
  let firstPixel = null;
  let allTransparent = colorType === 6;
  let allBlack = true;
  let singleColor = true;
  for (let rowIndex = 0; rowIndex < height; rowIndex += 1) {
    const filter = pixelData[sourceOffset];
    sourceOffset += 1;
    const row = Buffer.alloc(rowLength);
    for (let index = 0; index < rowLength; index += 1) {
      const encoded = pixelData[sourceOffset + index];
      const left = index >= bytesPerPixel ? row[index - bytesPerPixel] : 0;
      const above = previousRow[index];
      const upperLeft = index >= bytesPerPixel ? previousRow[index - bytesPerPixel] : 0;
      if (filter === 0) {
        row[index] = encoded;
      } else if (filter === 1) {
        row[index] = (encoded + left) & 0xff;
      } else if (filter === 2) {
        row[index] = (encoded + above) & 0xff;
      } else if (filter === 3) {
        row[index] = (encoded + Math.floor((left + above) / 2)) & 0xff;
      } else if (filter === 4) {
        row[index] = (encoded + paeth(left, above, upperLeft)) & 0xff;
      } else {
        fail(`PNG uses unsupported filter ${String(filter)}`);
      }
    }
    sourceOffset += rowLength;

    for (let index = 0; index < rowLength; index += bytesPerPixel) {
      const pixel = [row[index], row[index + 1], row[index + 2], colorType === 6 ? row[index + 3] : 255];
      if (firstPixel === null) {
        firstPixel = pixel;
      } else if (singleColor && pixel.some((value, component) => value !== firstPixel[component])) {
        singleColor = false;
      }
      if (pixel[3] !== 0) {
        allTransparent = false;
      }
      if (pixel[0] !== 0 || pixel[1] !== 0 || pixel[2] !== 0) {
        allBlack = false;
      }
    }
    previousRow = row;
  }

  if (allTransparent) {
    fail("capture is fully transparent");
  }
  if (allBlack) {
    fail("capture is fully black");
  }
  if (singleColor) {
    fail("capture is a single-color blank image");
  }

  return { width, height };
}

function gitHead() {
  const result = spawnSync("git", ["rev-parse", "HEAD"], {
    cwd: projectRoot,
    encoding: "utf8",
  });
  if (result.error !== undefined || result.status !== 0) {
    fail("could not resolve the current Git Head");
  }
  return result.stdout.trim();
}

function main() {
  const options = parseArguments(process.argv.slice(2));
  if (options.selfCheck) {
    runStaticSelfCheck();
    return;
  }

  runStaticSelfCheck();
  const outputDirectory = validateOutputDirectory(options.out);
  validateScene(options.scene);
  const runner = detectRunner();
  const godotVersion = requireSupportedGodot();
  const { resolvedProjectRoot, resolvedOutputDirectory } = resolveContainedOutputDirectory(outputDirectory);

  const artifact = join(resolvedOutputDirectory, ARTIFACT_NAME);
  const manifest = join(resolvedOutputDirectory, MANIFEST_NAME);
  rmSync(artifact, { force: true });
  rmSync(manifest, { force: true });

  try {
    const result = spawnSync(
      godot,
      ["--path", projectRoot, "--audio-driver", "Dummy", options.scene, "--", `--out=${artifact}`],
      { cwd: projectRoot, encoding: "utf8", env: environment },
    );
    process.stdout.write(`${result.stdout ?? ""}${result.stderr ?? ""}`);
    if (result.error !== undefined) {
      fail(`Godot renderer could not start: ${result.error.message}`);
    }
    if (result.status !== 0) {
      fail(`Godot renderer exited with status ${String(result.status)}`);
    }
    assertRegularFile(artifact, "visual capture");
    const image = inspectPng(artifact);
    const artifactRelativePath = relative(resolvedProjectRoot, artifact).split(sep).join("/");
    if (artifactRelativePath === ".." || artifactRelativePath.startsWith("../")) {
      fail("visual artifact is not repo-relative");
    }
    const manifestData = {
      contractVersion: CONTRACT_VERSION,
      title: "Tank Skirmish visual evidence bootstrap",
      standardAcceptance: STANDARD_ACCEPTANCE,
      gitHead: gitHead(),
      godotVersion,
      runner,
      viewport: { width: image.width, height: image.height, deviceScaleFactor: 1 },
      artifact: {
        path: artifactRelativePath,
        mediaType: "image/png",
        sha256: createHash("sha256").update(readFileSync(artifact)).digest("hex"),
        bytes: statSync(artifact).size,
      },
    };
    writeFileSync(manifest, `${JSON.stringify(manifestData, null, 2)}\n`, "utf8");
    console.log(`visual evidence written: ${artifactRelativePath}`);
  } catch (error) {
    rmSync(manifest, { force: true });
    rmSync(artifact, { force: true });
    throw error;
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    main();
  } catch (error) {
    console.error(`visual review failed: ${error.message}`);
    process.exitCode = 1;
  }
}
