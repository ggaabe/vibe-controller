import { readFile, writeFile, mkdir, cp } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

export const root = path.dirname(fileURLToPath(import.meta.url));
export const siteURL = "https://ggaabe.github.io/vibe-controller/";
const repo = "https://github.com/ggaabe/vibe-controller";

export function validateRelease(release) {
  if (!/^\d+\.\d+\.\d+$/.test(release.version))
    throw new Error("Invalid release version");
  if (release.url !== `${repo}/releases/tag/v${release.version}`)
    throw new Error("Invalid release URL");
  if (
    release.download !==
    `${repo}/releases/download/v${release.version}/Vibe-Controller-${release.version}-arm64.dmg`
  ) {
    throw new Error("Unexpected release asset");
  }
  return release;
}

export async function build({ refreshRelease = false } = {}) {
  let release = validateRelease(
    JSON.parse(await readFile(path.join(root, "release.json"), "utf8")),
  );
  if (refreshRelease) {
    const headers = {
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
    };
    if (process.env.GITHUB_TOKEN)
      headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
    const response = await fetch(
      "https://api.github.com/repos/ggaabe/vibe-controller/releases/latest",
      {
        headers,
        signal: AbortSignal.timeout(15000),
      },
    );
    if (!response.ok)
      throw new Error(`Release lookup failed: ${response.status}`);
    const current = await response.json();
    if (current.draft || current.prerelease)
      throw new Error("Public release required");
    const version = current.tag_name?.replace(/^v/, "");
    const asset = current.assets?.find(
      (a) =>
        a.name === `Vibe-Controller-${version}-arm64.dmg` &&
        a.state === "uploaded",
    );
    release = validateRelease({
      version,
      url: current.html_url,
      download: asset?.browser_download_url,
    });
  }
  const out = path.join(root, "dist");
  await mkdir(out, { recursive: true });
  await cp(path.join(root, "assets"), path.join(out, "assets"), {
    recursive: true,
  });
  const replacements = {
    VERSION: release.version,
    DOWNLOAD_URL: release.download,
    RELEASE_URL: release.url,
    SITE_URL: siteURL,
  };
  for (const family of ["xbox", "playstation"]) {
    const svg = await readFile(
      path.join(root, "assets", `${family}.svg`),
      "utf8",
    );
    // Multiple artwork families share gradient names. Namespace each instance.
    replacements[`${family.toUpperCase()}_SVG`] = svg
      .replace(/id="([^"]+)"/g, `id="${family}-$1"`)
      .replace(/url\(#([^)]+)\)/g, `url(#${family}-$1)`)
      .replace("<svg ", '<svg aria-hidden="true" focusable="false" ');
  }
  let html = await readFile(path.join(root, "index.html"), "utf8");
  html = html.replace(/\{\{([A-Z_]+)\}\}/g, (_, key) => {
    if (!(key in replacements)) throw new Error(`Unknown template key: ${key}`);
    return replacements[key];
  });
  await writeFile(path.join(out, "index.html"), html);
  for (const file of [
    "styles.css",
    "app.js",
    "404.html",
    "robots.txt",
    "sitemap.xml",
  ]) {
    await cp(path.join(root, file), path.join(out, file));
  }
  await writeFile(path.join(out, ".nojekyll"), "");
  await writeFile(
    path.join(out, "release.json"),
    `${JSON.stringify(release, null, 2)}\n`,
  );
  console.log(`Built Vibe Controller website for v${release.version} → ${out}`);
}

if (
  process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  await build({ refreshRelease: process.argv.includes("--refresh-release") });
}
