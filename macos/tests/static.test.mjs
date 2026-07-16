import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const node = process.execPath;

test("bundled macOS theme references a committed non-empty image", async () => {
  const theme = JSON.parse(await fs.readFile(path.join(root, "assets", "theme.json"), "utf8"));
  assert.equal(path.basename(theme.image), theme.image);
  const imagePath = path.join(root, "assets", theme.image);
  const stat = await fs.stat(imagePath);
  assert.equal(stat.isFile(), true);
  assert.ok(stat.size > 0);
});

test("macOS release version is synchronized", async () => {
  const version = (await fs.readFile(path.join(root, "VERSION"), "utf8")).trim();
  const packageJson = JSON.parse(await fs.readFile(path.join(root, "package.json"), "utf8"));
  const common = await fs.readFile(path.join(root, "scripts", "common-macos.sh"), "utf8");
  const injector = await fs.readFile(path.join(root, "scripts", "injector.mjs"), "utf8");
  assert.equal(packageJson.version, version);
  assert.match(common, new RegExp(`SKIN_VERSION=["']${version.replaceAll(".", "\\.")}["']`));
  assert.match(injector, new RegExp(`SKIN_VERSION = ["']${version.replaceAll(".", "\\.")}["']`));
});

test("theme config install preserves appearance and restore is exact", async (t) => {
  const temp = await fs.mkdtemp(path.join(os.tmpdir(), "dream-skin-config-"));
  t.after(() => fs.rm(temp, { recursive: true, force: true }));
  const config = path.join(temp, "config.toml");
  const backup = path.join(temp, "theme-backup.json");
  const original = [
    'model = "gpt-5"',
    "",
    "[desktop]",
    'appearanceTheme = "system"',
    'appearanceDarkCodeThemeId = "vscode-dark"',
    "keepMe = true",
    "",
  ].join("\n");
  await fs.writeFile(config, original);

  const install = spawnSync(node, [path.join(root, "scripts", "theme-config.mjs"), "install", config, backup], {
    encoding: "utf8",
  });
  assert.equal(install.status, 0, install.stderr);
  assert.equal(await fs.readFile(config, "utf8"), original);

  const restore = spawnSync(node, [path.join(root, "scripts", "theme-config.mjs"), "restore", config, backup], {
    encoding: "utf8",
  });
  assert.equal(restore.status, 0, restore.stderr);
  assert.equal(await fs.readFile(config, "utf8"), original);
});
