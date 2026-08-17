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
  assertNonEmptyString(value.version, fieldPath(path, "version"));
  assertNonEmptyString(value.channel, fieldPath(path, "channel"));
  validateArchive(value.archive, fieldPath(path, "archive"));
  validateInstall(value.install, fieldPath(path, "install"));
  validateProvenance(value.provenance, fieldPath(path, "provenance"));
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
    validateTool(tool, path);
    if (seenIds.has(tool.id)) {
      fail(`${path}.id`);
    }
    seenIds.add(tool.id);
  }
  if (seenIds.size !== EXPECTED_TOOL_IDS.size) {
    fail("tools");
  }

  return deepFreeze(value);
}
