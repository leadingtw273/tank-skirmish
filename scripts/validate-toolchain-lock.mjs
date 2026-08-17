const ROOT_FIELDS = ["schemaVersion", "target", "tools"];
const TOOL_FIELDS = ["id", "version", "channel", "archive", "install", "provenance"];
const ARCHIVE_FIELDS = [
  "filename",
  "format",
  "sizeBytes",
  "memberCount",
  "topLevelDirectory",
  "exactMemberNames",
  "allowedEntryTypes",
  "url",
  "checksumSourceUrl",
  "checksum",
];
const INSTALL_FIELDS = [
  "cacheRelativePath",
  "executableRelativePath",
  "executableChecksum",
  "versionContract",
];
const PROVENANCE_FIELDS = ["method", "verifiedAt", "verifiedBy"];
const CHECKSUM_FIELDS = ["algorithm", "value"];
const GODOT_VERSION_CONTRACT_FIELDS = ["mode", "value"];
const BLENDER_VERSION_CONTRACT_FIELDS = ["mode", "firstLine", "buildHash"];
const EXPECTED_TOOL_IDS = new Set(["godot", "blender"]);

function fail(path) {
  throw new Error(path);
}

function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function fieldPath(parent, field) {
  return parent === "" ? field : `${parent}.${field}`;
}

function assertExactFields(value, fields, path) {
  if (!isRecord(value)) {
    fail(path || "root");
  }

  for (const field of fields) {
    if (!Object.hasOwn(value, field)) {
      fail(fieldPath(path, field));
    }
  }

  for (const field of Object.keys(value)) {
    if (!fields.includes(field)) {
      fail(fieldPath(path, field));
    }
  }
}

function assertNonEmptyString(value, path) {
  if (typeof value !== "string" || value.length === 0) {
    fail(path);
  }
}

function assertInteger(value, path, minimum) {
  if (!Number.isSafeInteger(value) || value < minimum) {
    fail(path);
  }
}

function assertSafeRelativePosixPath(value, path) {
  assertNonEmptyString(value, path);
  if (
    value.includes("\0") ||
    value.includes("\\") ||
    value.startsWith("/") ||
    value.endsWith("/") ||
    /^[A-Za-z]:/.test(value)
  ) {
    fail(path);
  }

  if (value.split("/").some((segment) => segment === "" || segment === "." || segment === "..")) {
    fail(path);
  }
}

function assertSafePathSegment(value, path) {
  assertSafeRelativePosixPath(value, path);
  if (value.includes("/")) {
    fail(path);
  }
}

function assertExactUrl(value, path, expectedHost, expectedPathname) {
  assertNonEmptyString(value, path);

  let url;
  try {
    url = new URL(value);
  } catch {
    fail(path);
  }

  const authority = value.slice(value.indexOf("//") + 2).split(/[/?#]/u, 1)[0];
  if (
    url.protocol !== "https:" ||
    url.username !== "" ||
    url.password !== "" ||
    url.port !== "" ||
    url.search !== "" ||
    url.hash !== "" ||
    authority !== expectedHost ||
    url.hostname !== expectedHost ||
    url.pathname !== expectedPathname
  ) {
    fail(path);
  }
}

function assertChecksum(value, path, permittedAlgorithms) {
  assertExactFields(value, CHECKSUM_FIELDS, path);
  const algorithmPath = fieldPath(path, "algorithm");
  const digestPath = fieldPath(path, "value");
  const algorithm = value.algorithm;
  if (!permittedAlgorithms.has(algorithm)) {
    fail(algorithmPath);
  }

  const expectedLength = algorithm === "sha256" ? 64 : 128;
  if (typeof value.value !== "string" || !new RegExp(`^[0-9a-f]{${expectedLength}}$`, "u").test(value.value)) {
    fail(digestPath);
  }
}

function assertRoundTripDate(value, path) {
  if (!/^\d{4}-\d{2}-\d{2}$/u.test(value)) {
    fail(path);
  }
  const date = new Date(`${value}T00:00:00.000Z`);
  if (Number.isNaN(date.valueOf()) || date.toISOString().slice(0, 10) !== value) {
    fail(path);
  }
}

function validateArchive(value, path) {
  assertExactFields(value, ARCHIVE_FIELDS, path);
  assertNonEmptyString(value.filename, fieldPath(path, "filename"));
  assertNonEmptyString(value.format, fieldPath(path, "format"));
  assertInteger(value.sizeBytes, fieldPath(path, "sizeBytes"), 1);
  assertInteger(value.memberCount, fieldPath(path, "memberCount"), 0);
  if (value.topLevelDirectory !== null) {
    assertNonEmptyString(value.topLevelDirectory, fieldPath(path, "topLevelDirectory"));
  }
  if (value.exactMemberNames !== null && !Array.isArray(value.exactMemberNames)) {
    fail(fieldPath(path, "exactMemberNames"));
  }
  if (!Array.isArray(value.allowedEntryTypes)) {
    fail(fieldPath(path, "allowedEntryTypes"));
  }
  assertNonEmptyString(value.url, fieldPath(path, "url"));
  assertNonEmptyString(value.checksumSourceUrl, fieldPath(path, "checksumSourceUrl"));
  assertChecksum(value.checksum, fieldPath(path, "checksum"), new Set(["sha256", "sha512"]));
}

function validateInstall(value, path) {
  assertExactFields(value, INSTALL_FIELDS, path);
  assertSafeRelativePosixPath(value.cacheRelativePath, fieldPath(path, "cacheRelativePath"));
  assertSafeRelativePosixPath(value.executableRelativePath, fieldPath(path, "executableRelativePath"));
  assertChecksum(value.executableChecksum, fieldPath(path, "executableChecksum"), new Set(["sha256"]));
}

function validateGodot(tool, path) {
  const archivePath = fieldPath(path, "archive");
  const installPath = fieldPath(path, "install");
  const version = tool.version;
  const channel = tool.channel;
  const filename = `Godot_v${version}-${channel}_linux.x86_64.zip`;
  const executable = `Godot_v${version}-${channel}_linux.x86_64`;
  const downloadDirectory = `/godotengine/godot-builds/releases/download/${version}-${channel}`;

  if (channel !== "stable") {
    fail(fieldPath(path, "channel"));
  }
  assertSafePathSegment(tool.archive.filename, fieldPath(archivePath, "filename"));
  if (tool.archive.filename !== filename) {
    fail(fieldPath(archivePath, "filename"));
  }
  if (tool.archive.format !== "zip") {
    fail(fieldPath(archivePath, "format"));
  }
  if (tool.archive.topLevelDirectory !== null) {
    fail(fieldPath(archivePath, "topLevelDirectory"));
  }
  if (!Array.isArray(tool.archive.exactMemberNames) || tool.archive.exactMemberNames.length !== 1) {
    fail(fieldPath(archivePath, "exactMemberNames"));
  }
  assertSafeRelativePosixPath(tool.archive.exactMemberNames[0], fieldPath(archivePath, "exactMemberNames"));
  if (tool.archive.exactMemberNames[0] !== executable) {
    fail(fieldPath(archivePath, "exactMemberNames"));
  }
  if (tool.archive.memberCount !== tool.archive.exactMemberNames.length) {
    fail(fieldPath(archivePath, "memberCount"));
  }
  if (JSON.stringify(tool.archive.allowedEntryTypes) !== JSON.stringify(["regular_file"])) {
    fail(fieldPath(archivePath, "allowedEntryTypes"));
  }
  assertExactUrl(tool.archive.url, fieldPath(archivePath, "url"), "github.com", `${downloadDirectory}/${filename}`);
  assertExactUrl(tool.archive.checksumSourceUrl, fieldPath(archivePath, "checksumSourceUrl"), "github.com", `${downloadDirectory}/SHA512-SUMS.txt`);
  if (tool.archive.checksum.algorithm !== "sha512") {
    fail(fieldPath(archivePath, "checksum.algorithm"));
  }
  if (tool.install.executableRelativePath !== executable) {
    fail(fieldPath(installPath, "executableRelativePath"));
  }

  const versionContractPath = fieldPath(installPath, "versionContract");
  assertExactFields(tool.install.versionContract, GODOT_VERSION_CONTRACT_FIELDS, versionContractPath);
  if (tool.install.versionContract.mode !== "exact_output") {
    fail(fieldPath(versionContractPath, "mode"));
  }
  const outputPrefix = `${version}.${channel}.official.`;
  if (
    typeof tool.install.versionContract.value !== "string" ||
    !tool.install.versionContract.value.startsWith(outputPrefix) ||
    !/^[0-9a-f]+$/u.test(tool.install.versionContract.value.slice(outputPrefix.length))
  ) {
    fail(fieldPath(versionContractPath, "value"));
  }
}

function validateBlender(tool, path) {
  const archivePath = fieldPath(path, "archive");
  const installPath = fieldPath(path, "install");
  const version = tool.version;
  const [major, minor] = version.split(".");
  const filename = `blender-${version}-linux-x64.tar.xz`;
  const topLevelDirectory = `blender-${version}-linux-x64`;
  const downloadDirectory = `/release/Blender${major}.${minor}`;

  if (tool.channel !== "lts") {
    fail(fieldPath(path, "channel"));
  }
  assertSafePathSegment(tool.archive.filename, fieldPath(archivePath, "filename"));
  if (tool.archive.filename !== filename) {
    fail(fieldPath(archivePath, "filename"));
  }
  if (tool.archive.format !== "tar.xz") {
    fail(fieldPath(archivePath, "format"));
  }
  assertSafePathSegment(tool.archive.topLevelDirectory, fieldPath(archivePath, "topLevelDirectory"));
  if (tool.archive.topLevelDirectory !== topLevelDirectory) {
    fail(fieldPath(archivePath, "topLevelDirectory"));
  }
  if (tool.archive.exactMemberNames !== null) {
    fail(fieldPath(archivePath, "exactMemberNames"));
  }
  if (JSON.stringify(tool.archive.allowedEntryTypes) !== JSON.stringify(["regular_file", "directory", "symlink"])) {
    fail(fieldPath(archivePath, "allowedEntryTypes"));
  }
  assertExactUrl(tool.archive.url, fieldPath(archivePath, "url"), "download.blender.org", `${downloadDirectory}/${filename}`);
  assertExactUrl(tool.archive.checksumSourceUrl, fieldPath(archivePath, "checksumSourceUrl"), "download.blender.org", `${downloadDirectory}/blender-${version}.sha256`);
  if (tool.archive.checksum.algorithm !== "sha256") {
    fail(fieldPath(archivePath, "checksum.algorithm"));
  }
  if (tool.install.executableRelativePath !== `${topLevelDirectory}/blender`) {
    fail(fieldPath(installPath, "executableRelativePath"));
  }

  const versionContractPath = fieldPath(installPath, "versionContract");
  assertExactFields(tool.install.versionContract, BLENDER_VERSION_CONTRACT_FIELDS, versionContractPath);
  if (tool.install.versionContract.mode !== "first_line_and_build_hash") {
    fail(fieldPath(versionContractPath, "mode"));
  }
  if (tool.install.versionContract.firstLine !== `Blender ${version} LTS`) {
    fail(fieldPath(versionContractPath, "firstLine"));
  }
  if (typeof tool.install.versionContract.buildHash !== "string" || !/^[0-9a-f]{12}$/u.test(tool.install.versionContract.buildHash)) {
    fail(fieldPath(versionContractPath, "buildHash"));
  }
}

function validateProvenance(value, path) {
  assertExactFields(value, PROVENANCE_FIELDS, path);
  if (value.method !== "archive-extracted") {
    fail(fieldPath(path, "method"));
  }
  if (typeof value.verifiedAt !== "string") {
    fail(fieldPath(path, "verifiedAt"));
  }
  assertRoundTripDate(value.verifiedAt, fieldPath(path, "verifiedAt"));
  if (value.verifiedBy !== "team_lead") {
    fail(fieldPath(path, "verifiedBy"));
  }
}

function validateTool(value, path) {
  assertExactFields(value, TOOL_FIELDS, path);
  if (!EXPECTED_TOOL_IDS.has(value.id)) {
    fail(fieldPath(path, "id"));
  }
  if (typeof value.version !== "string" || !/^\d+\.\d+\.\d+$/u.test(value.version)) {
    fail(fieldPath(path, "version"));
  }
  assertNonEmptyString(value.channel, fieldPath(path, "channel"));
  validateArchive(value.archive, fieldPath(path, "archive"));
  validateInstall(value.install, fieldPath(path, "install"));
  validateProvenance(value.provenance, fieldPath(path, "provenance"));
  if (value.id === "godot") {
    validateGodot(value, path);
  } else {
    validateBlender(value, path);
  }
}

function deepFreeze(value, seen = new WeakSet()) {
  if (value === null || typeof value !== "object" || seen.has(value)) {
    return value;
  }
  seen.add(value);
  for (const child of Object.values(value)) {
    deepFreeze(child, seen);
  }
  return Object.freeze(value);
}

export function validateToolchainLock(value) {
  assertExactFields(value, ROOT_FIELDS, "");
  if (value.schemaVersion !== 1) {
    fail("schemaVersion");
  }
  if (value.target !== "linux-x64") {
    fail("target");
  }
  if (!Array.isArray(value.tools) || value.tools.length !== EXPECTED_TOOL_IDS.size) {
    fail("tools");
  }

  const seenIds = new Set();
  for (const [index, tool] of value.tools.entries()) {
    const path = `tools[${index}]`;
    if (seenIds.has(tool.id)) {
      fail(`${path}.id`);
    }
    validateTool(tool, path);
    seenIds.add(tool.id);
  }
  if (seenIds.size !== EXPECTED_TOOL_IDS.size) {
    fail("tools");
  }

  return deepFreeze(value);
}
