import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile, stat } from "node:fs/promises";
import path from "node:path";
import { validateRelease, root } from "../build.mjs";
test("release links are constrained to the official versioned Apple-silicon DMG", async () => {
  const good = JSON.parse(
    await readFile(path.join(root, "release.json"), "utf8"),
  );
  assert.equal(validateRelease(good).version, good.version);
  assert.throws(() => validateRelease({ ...good, version: "<script>" }));
  assert.throws(() =>
    validateRelease({ ...good, download: "https://example.com/installer.dmg" }),
  );
  assert.throws(() =>
    validateRelease({ ...good, url: "https://example.com/release" }),
  );
});
test("built HTML resolves all templates and uses project-relative assets", async () => {
  const html = await readFile(path.join(root, "dist/index.html"), "utf8");
  assert.doesNotMatch(html, /\{\{[A-Z_]+\}\}/);
  assert.match(html, /https:\/\/ggaabe.github.io\/vibe-controller\//);
  assert.match(html, /releases\/download\/v\d+\.\d+\.\d+\/Vibe-Controller-/);
  for (const match of html.matchAll(
    /(?:src|href)="(assets\/[^"#]+|app\.js|styles\.css)"/g,
  )) {
    assert.ok(
      (await stat(path.join(root, "dist", match[1]))).isFile(),
      match[1],
    );
  }
  const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map((m) => m[1]);
  assert.equal(
    new Set(ids).size,
    ids.length,
    "No duplicate SVG or document IDs",
  );
});
