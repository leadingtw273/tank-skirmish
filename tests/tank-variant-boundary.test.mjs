import assert from "node:assert/strict";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join, resolve } from "node:path";
import test from "node:test";

const projectRoot = resolve(import.meta.dirname, "..");
const tankRoot = join(projectRoot, "src", "actors", "tank");

function collectFiles(directory) {
  const files = [];
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    if (entry.name === "variants") continue;
    const path = join(directory, entry.name);
    if (entry.isDirectory()) files.push(...collectFiles(path));
    else files.push(path);
  }
  return files;
}

test("common tank layer contains no vehicle or vendor node names", () => {
  const forbidden = /\bTank[1-4]\b|AgentTeamScaleRoot|Tank_Turret|Tank_Gun/u;
  for (const path of collectFiles(tankRoot)) {
    assert.doesNotMatch(readFileSync(path, "utf8"), forbidden, path);
  }
});

test("only the Tank2 variant owns Tank2 scenes and damage choreography", () => {
  assert.equal(existsSync(join(tankRoot, "tank.tscn")), false);
  assert.equal(existsSync(join(tankRoot, "tank_base.tscn")), true);
  assert.equal(existsSync(join(tankRoot, "variants", "tank2", "tank2.tscn")), true);
  assert.equal(existsSync(join(tankRoot, "variants", "tank2", "damage", "tank2_damage_visuals.tscn")), true);
  assert.equal(existsSync(join(projectRoot, "src", "vfx", "damage", "tank2_damage_visuals.tscn")), false);
});
