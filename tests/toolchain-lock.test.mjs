import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  ToolchainLockLoadError,
  loadAndValidateToolchainLock,
  runToolchainLockCli,
  validateToolchainLock,
} from "../scripts/validate-toolchain-lock.mjs";

const fixture = JSON.parse(
  readFileSync(new URL("../docs/toolchain-lock.json", import.meta.url), "utf8"),
);

function lock() {
  return structuredClone(fixture);
}

function expectPath(mutator, path) {
  const value = lock();
  mutator(value);
  assert.throws(() => validateToolchainLock(value), { message: path });
}

function toolById(value, id) {
  return value.tools.find((tool) => tool.id === id);
}

function expectToolPath(id, mutator, suffix) {
  const value = lock();
  const index = value.tools.findIndex((tool) => tool.id === id);
  mutator(value.tools[index]);
  assert.throws(() => validateToolchainLock(value), { message: `tools[${index}].${suffix}` });
}

function updateDerivedFields(tool, version) {
  tool.version = version;
  const [major, minor] = version.split(".");
  if (tool.id === "godot") {
    tool.archive.filename = `Godot_v${version}-${tool.channel}_linux.x86_64.zip`;
    tool.archive.url = `https://github.com/godotengine/godot-builds/releases/download/${version}-${tool.channel}/${tool.archive.filename}`;
    tool.archive.checksumSourceUrl = `https://github.com/godotengine/godot-builds/releases/download/${version}-${tool.channel}/SHA512-SUMS.txt`;
    tool.archive.exactMemberNames = [`Godot_v${version}-${tool.channel}_linux.x86_64`];
    tool.install.executableRelativePath = tool.archive.exactMemberNames[0];
    tool.install.versionContract.value = `${version}.${tool.channel}.official.a13da4feb`;
  } else {
    tool.archive.filename = `blender-${version}-linux-x64.tar.xz`;
    tool.archive.topLevelDirectory = `blender-${version}-linux-x64`;
    tool.archive.url = `https://download.blender.org/release/Blender${major}.${minor}/${tool.archive.filename}`;
    tool.archive.checksumSourceUrl = `https://download.blender.org/release/Blender${major}.${minor}/blender-${version}.sha256`;
    tool.install.executableRelativePath = `${tool.archive.topLevelDirectory}/blender`;
    tool.install.versionContract.firstLine = `Blender ${version} LTS`;
  }
}

function expectLoadError(error, code, path) {
  assert.equal(error instanceof ToolchainLockLoadError, true);
  assert.equal(error.code, code);
  assert.equal(error.path, path);
  assert.doesNotMatch(error.message, /Toolchain lock source|SyntaxError|at /u);
  return true;
}

function memoryStream() {
  let value = "";
  return {
    stream: { write: (chunk) => { value += chunk; } },
    value: () => value,
  };
}

test("accepts the lock and recursively deep-freezes it", () => {
  const value = lock();
  const result = validateToolchainLock(value);

  assert.equal(result, value);
  assert.equal(Object.isFrozen(value), true);
  assert.equal(Object.isFrozen(value.tools), true);
  assert.equal(Object.isFrozen(value.tools[0].archive), true);
  assert.equal(Object.isFrozen(value.tools[0].install.executableChecksum), true);
  assert.throws(() => {
    value.tools[0].version = "mutated";
  }, TypeError);
});

test("rejects root fields, required tool fields, and duplicate tools with stable paths", () => {
  expectPath((value) => {
    value.extra = true;
  }, "extra");
  expectPath((value) => {
    delete value.target;
  }, "target");
  expectPath((value) => {
    value.schemaVersion = 2;
  }, "schemaVersion");
  expectPath((value) => {
    value.target = "darwin-arm64";
  }, "target");
  expectPath((value) => {
    delete value.tools[0].version;
  }, "tools[0].version");
  expectPath((value) => {
    value.tools[0].unknown = true;
  }, "tools[0].unknown");
  expectPath((value) => {
    value.tools[1].id = "godot";
  }, "tools[1].id");
  expectPath((value) => {
    value.tools = [value.tools[0]];
  }, "tools");
});

test("rejects invalid archive and checksum values with field paths", () => {
  expectPath((value) => {
    delete value.tools[0].archive.url;
  }, "tools[0].archive.url");
  expectPath((value) => {
    value.tools[0].archive.extra = true;
  }, "tools[0].archive.extra");
  expectPath((value) => {
    value.tools[0].archive.sizeBytes = 1.5;
  }, "tools[0].archive.sizeBytes");
  expectPath((value) => {
    value.tools[0].archive.memberCount = -1;
  }, "tools[0].archive.memberCount");
  expectPath((value) => {
    value.tools[0].archive.checksum.algorithm = "md5";
  }, "tools[0].archive.checksum.algorithm");
  expectPath((value) => {
    value.tools[0].archive.checksum.value = "A".repeat(128);
  }, "tools[0].archive.checksum.value");
  expectPath((value) => {
    value.tools[0].install.executableChecksum.value = "a".repeat(128);
  }, "tools[0].install.executableChecksum.value");
});

test("rejects unsafe install paths", () => {
  for (const invalidPath of ["/cache", "cache/", "cache//tool", "cache/./tool", "cache/../tool", "cache\\tool", "C:tool", "cache\0tool"]) {
    expectPath((value) => {
      value.tools[0].install.cacheRelativePath = invalidPath;
    }, "tools[0].install.cacheRelativePath");
  }

  expectPath((value) => {
    value.tools[0].install.executableRelativePath = "../Godot";
  }, "tools[0].install.executableRelativePath");
});

test("rejects missing install fields and invalid provenance", () => {
  expectPath((value) => {
    delete value.tools[0].install.executableChecksum;
  }, "tools[0].install.executableChecksum");
  expectPath((value) => {
    value.tools[0].install.unknown = true;
  }, "tools[0].install.unknown");
  expectPath((value) => {
    delete value.tools[0].provenance.verifiedBy;
  }, "tools[0].provenance.verifiedBy");
  expectPath((value) => {
    value.tools[0].provenance.method = "manual";
  }, "tools[0].provenance.method");
  expectPath((value) => {
    value.tools[0].provenance.verifiedAt = "2026-02-30";
  }, "tools[0].provenance.verifiedAt");
  expectPath((value) => {
    value.tools[0].provenance.verifiedBy = "other";
  }, "tools[0].provenance.verifiedBy");
});

test("enforces each vendor's channel and archive filename", () => {
  for (const { id, channel, filename } of [
    { id: "godot", channel: "beta", filename: "Godot_v4.7.1-stable_linux.x86_64.zip.bak" },
    { id: "blender", channel: "stable", filename: "blender-4.5.12-linux-x64.tar.xz.bak" },
  ]) {
    expectToolPath(id, (tool) => {
      tool.channel = channel;
    }, "channel");
    expectToolPath(id, (tool) => {
      tool.archive.filename = filename;
    }, "archive.filename");
    expectToolPath(id, (tool) => {
      tool.archive.filename = "../archive";
    }, "archive.filename");
  }
});

test("enforces three-component versions and accepts consistently derived versions", () => {
  for (const id of ["godot", "blender"]) {
    for (const version of ["4.7", "4.7.1.2", "v4.7.1", "4.7.x"]) {
      expectToolPath(id, (tool) => {
        tool.version = version;
      }, "version");
    }

    const value = lock();
    updateDerivedFields(toolById(value, id), id === "godot" ? "5.10.3" : "6.11.12");
    assert.doesNotThrow(() => validateToolchainLock(value));
  }
});

test("rejects every forbidden archive URL component for both vendors", () => {
  const mutations = [
    ["unparseable URL", () => "not a URL"],
    ["userinfo", (url) => url.replace("https://", "https://user@")],
    ["explicit port", (url) => url.replace(/^(https:\/\/[^/]+)/u, "$1:444")],
    ["explicit default port", (url) => url.replace(/^(https:\/\/[^/]+)/u, "$1:443")],
    ["host", (url) => url.replace("github.com", "example.com").replace("download.blender.org", "example.com")],
    ["pathname", (url) => `${url}/extra`],
    ["query", (url) => `${url}?download=1`],
    ["fragment", (url) => `${url}#checksum`],
  ];

  for (const id of ["godot", "blender"]) {
    for (const [, mutateUrl] of mutations) {
      expectToolPath(id, (tool) => {
        tool.archive.url = mutateUrl(tool.archive.url);
      }, "archive.url");
    }
  }
});

test("enforces checksum sources, archive discriminants, and executable crossings", () => {
  for (const id of ["godot", "blender"]) {
    for (const mutateUrl of [
      () => "not a URL",
      (url) => url.replace("https://", "https://user@"),
      (url) => url.replace(/^(https:\/\/[^/]+)/u, "$1:444"),
      (url) => url.replace(/^(https:\/\/[^/]+)/u, "$1:443"),
      (url) => url.replace("github.com", "example.com").replace("download.blender.org", "example.com"),
      (url) => {
        const parsed = new URL(url);
        parsed.pathname = `/other/${parsed.pathname.split("/").at(-1)}`;
        return parsed.href;
      },
      (url) => url.replace(/\/[^/]+$/u, "/other.txt"),
      (url) => `${url}?download=1`,
      (url) => `${url}#checksum`,
    ]) {
      expectToolPath(id, (tool) => {
        tool.archive.checksumSourceUrl = mutateUrl(tool.archive.checksumSourceUrl);
      }, "archive.checksumSourceUrl");
    }
  }

  for (const { id, format, entryTypes, mutateCross } of [
    {
      id: "godot",
      format: "tar.xz",
      entryTypes: ["regular"],
      mutateCross: (tool) => {
        tool.archive.exactMemberNames = ["other-executable"];
      },
    },
    {
      id: "blender",
      format: "zip",
      entryTypes: ["regular_file", "directory"],
      mutateCross: (tool) => {
        tool.install.executableRelativePath = `${tool.archive.topLevelDirectory}/bin/blender`;
      },
    },
  ]) {
    expectToolPath(id, (tool) => {
      tool.archive.format = format;
    }, "archive.format");
    expectToolPath(id, (tool) => {
      tool.archive.allowedEntryTypes = entryTypes;
    }, "archive.allowedEntryTypes");
    expectToolPath(id, mutateCross, id === "godot" ? "archive.exactMemberNames" : "install.executableRelativePath");
    expectToolPath(id, (tool) => {
      tool.archive.checksum.algorithm = id === "godot" ? "sha256" : "sha512";
      tool.archive.checksum.value = "a".repeat(id === "godot" ? 64 : 128);
    }, "archive.checksum.algorithm");
  }

  expectToolPath("godot", (tool) => {
    tool.archive.memberCount = 2;
  }, "archive.memberCount");
  expectToolPath("godot", (tool) => {
    tool.archive.topLevelDirectory = "Godot";
  }, "archive.topLevelDirectory");
  expectToolPath("godot", (tool) => {
    tool.install.executableRelativePath = "other-executable";
  }, "install.executableRelativePath");
  expectToolPath("blender", (tool) => {
    tool.archive.topLevelDirectory = "blender/4.5.12";
  }, "archive.topLevelDirectory");
});

test("enforces exact vendor version contracts with stable field paths", () => {
  for (const id of ["godot", "blender"]) {
    expectToolPath(id, (tool) => {
      delete tool.install.versionContract;
    }, "install.versionContract");
  }

  for (const { id, cases } of [
    {
      id: "godot",
      cases: [
        [(contract) => delete contract.value, "value"],
        [(contract) => { contract.unknown = true; }, "unknown"],
        [(contract) => { contract.mode = "first_line_and_build_hash"; }, "mode"],
        [(contract) => { contract.value = ""; }, "value"],
        [(contract) => { contract.value = "4.7.1.stable.official.A13DA4FEB"; }, "value"],
        [(contract) => { contract.value = "4.7.1.stable.official."; }, "value"],
      ],
    },
    {
      id: "blender",
      cases: [
        [(contract) => delete contract.buildHash, "buildHash"],
        [(contract) => { contract.unknown = true; }, "unknown"],
        [(contract) => { contract.mode = "exact_output"; }, "mode"],
        [(contract) => { contract.firstLine = "Blender 4.5.12"; }, "firstLine"],
        [(contract) => { contract.buildHash = "84AFD5F785F7"; }, "buildHash"],
        [(contract) => { contract.buildHash = "84afd5f785f"; }, "buildHash"],
      ],
    },
  ]) {
    for (const [mutateContract, field] of cases) {
      expectToolPath(id, (tool) => {
        mutateContract(tool.install.versionContract);
      }, `install.versionContract.${field}`);
    }
  }
});

test("loads, validates, and deep-freezes a lock from the caller path", async (t) => {
  const directory = await mkdtemp(join(tmpdir(), "toolchain-lock-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const path = join(directory, "valid.json");
  await writeFile(path, JSON.stringify(lock()), "utf8");

  const result = await loadAndValidateToolchainLock(path);
  assert.equal(Object.isFrozen(result), true);
  assert.equal(Object.isFrozen(result.tools[0].archive), true);
});

test("reports stable loader errors without exposing source or stacks", async (t) => {
  const directory = await mkdtemp(join(tmpdir(), "toolchain-lock-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const missingPath = join(directory, "missing.json");
  const invalidJsonPath = join(directory, "invalid-json.json");
  const invalidSchemaPath = join(directory, "invalid-schema.json");
  await writeFile(invalidJsonPath, "{ not json", "utf8");
  const invalidSchema = lock();
  invalidSchema.schemaVersion = 2;
  await writeFile(invalidSchemaPath, JSON.stringify(invalidSchema), "utf8");

  await assert.rejects(
    loadAndValidateToolchainLock(missingPath),
    (error) => expectLoadError(error, "io_error", missingPath),
  );
  await assert.rejects(
    loadAndValidateToolchainLock(invalidJsonPath),
    (error) => expectLoadError(error, "parse_error", invalidJsonPath),
  );
  await assert.rejects(
    loadAndValidateToolchainLock(invalidSchemaPath),
    (error) => expectLoadError(error, "validation_error", "schemaVersion"),
  );
});

test("CLI seam returns load errors through injected streams", async (t) => {
  const directory = await mkdtemp(join(tmpdir(), "toolchain-lock-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const missingPath = join(directory, "missing.json");
  const stdout = memoryStream();
  const stderr = memoryStream();

  const exitCode = await runToolchainLockCli(["--check"], {
    lockPath: missingPath,
    stdout: stdout.stream,
    stderr: stderr.stream,
  });

  assert.equal(exitCode, 1);
  assert.equal(stdout.value(), "");
  assert.equal(stderr.value(), `${JSON.stringify({ ok: false, code: "io_error", path: missingPath })}\n`);
});

test("CLI is cwd-independent and enforces exact argument usage", async (t) => {
  const directory = await mkdtemp(join(tmpdir(), "toolchain-lock-cwd-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const scriptPath = fileURLToPath(new URL("../scripts/validate-toolchain-lock.mjs", import.meta.url));
  const usage = `${JSON.stringify({ ok: false, code: "usage_error", path: "argv" })}\n`;

  const valid = spawnSync(process.execPath, [scriptPath, "--check"], {
    cwd: directory,
    encoding: "utf8",
  });
  if (valid.error?.code === "EPERM") {
    t.skip("execution sandbox blocks nested process creation");
    return;
  }
  assert.equal(valid.status, 0);
  assert.equal(valid.stdout, `${JSON.stringify({ ok: true, schemaVersion: 1, target: "linux-x64", tools: ["godot", "blender"] })}\n`);
  assert.equal(valid.stderr, "");

  for (const args of [[], ["--unknown"], ["--check", "extra"]]) {
    const result = spawnSync(process.execPath, [scriptPath, ...args], {
      cwd: directory,
      encoding: "utf8",
    });
    assert.equal(result.status, 2);
    assert.equal(result.stdout, "");
    assert.equal(result.stderr, usage);
  }
});

test("importing the module has no process-visible output", () => {
  const scriptUrl = new URL("../scripts/validate-toolchain-lock.mjs", import.meta.url).href;
  const result = spawnSync(process.execPath, ["--input-type=module", "--eval", `import ${JSON.stringify(scriptUrl)};`], {
    encoding: "utf8",
  });

  assert.equal(result.status, 0);
  assert.equal(result.stdout, "");
  assert.equal(result.stderr, "");
});
