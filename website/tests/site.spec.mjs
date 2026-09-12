import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

test("loads under the GitHub Pages project path without errors or missing assets", async ({
  page,
}) => {
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  page.on("response", (response) => {
    if (response.status() >= 400)
      errors.push(`${response.status()} ${response.url()}`);
  });
  await page.goto("./");
  await expect(page).toHaveTitle(/Vibe Controller/);
  await expect(page.locator("h1")).toHaveText("VibeController.");
  expect(
    await page
      .locator("img")
      .evaluateAll((images) =>
        images.every((img) => img.complete && img.naturalWidth > 0),
      ),
  ).toBe(true);
  expect(errors).toEqual([]);
  for (const size of [
    { width: 320, height: 812 },
    { width: 390, height: 844 },
    { width: 768, height: 1024 },
    { width: 1024, height: 768 },
    { width: 1440, height: 1000 },
    { width: 1920, height: 1080 },
  ]) {
    await page.setViewportSize(size);
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
      `No horizontal overflow at ${size.width}`,
    ).toBe(true);
  }
});
test("interactive workflow, controller layout, mappings, color and handoff work", async ({
  page,
}) => {
  await page.goto("./");
  await page.getByRole("button", { name: /Say what you want/ }).click();
  await expect(page.locator(".demo-window")).toHaveAttribute(
    "data-demo",
    "dictate",
  );
  await expect(page.locator("#workflow-caption")).toContainText(
    "dictation shortcut",
  );
  await page.getByRole("button", { name: /Send it on its way/ }).click();
  await expect(page.locator(".demo-window")).toHaveAttribute(
    "data-demo",
    "send",
  );
  await page.getByRole("button", { name: "PlayStation", exact: true }).click();
  await expect(page.locator("#playstation-art")).toBeVisible();
  await expect(page.locator("#xbox-art")).toBeHidden();
  await page
    .getByRole("button", { name: "Triangle: paste", exact: true })
    .click();
  await expect(page.locator("#mapping-key")).toHaveText("Triangle");
  await expect(page.locator("#mapping-shortcut")).toContainText("⌘ V");
  await page
    .getByRole("button", { name: "White controller", exact: true })
    .click();
  await expect(page.locator("#playstation-white stop").first()).toHaveAttribute(
    "stop-color",
    "#FFFFFF",
  );
  await page.getByRole("button", { name: /Move to the next Mac/ }).click();
  await expect(page.locator("#handoff-status")).toHaveText(
    "Pointer on the second Mac",
  );
  await page.getByRole("button", { name: /Move to the next Mac/ }).click();
  await expect(page.locator("#handoff-status")).toHaveText(
    "Pointer on another Mac",
  );
  await page.getByRole("button", { name: /Move to the next Mac/ }).click();
  await expect(page.locator("#handoff-status")).toHaveText(
    "Pointer on the lead Mac",
  );
});
test("FAQ and download links have useful accessible behavior", async ({
  page,
}) => {
  await page.goto("./");
  await page
    .getByText("Are dictation and OCR built in?", { exact: false })
    .click();
  await expect(page.locator("details[open]")).toContainText(
    "separate and not included",
  );
  const links = await page
    .getByRole("link", {
      name: /Download for Mac|Get Vibe Controller|Download Vibe Controller for/,
    })
    .evaluateAll((links) => links.map((a) => a.href));
  expect(links.length).toBeGreaterThanOrEqual(3);
  for (const href of links)
    expect(href).toMatch(
      /^https:\/\/github.com\/ggaabe\/vibe-controller\/releases\/download\/v\d+\.\d+\.\d+\/Vibe-Controller-\d+\.\d+\.\d+-arm64.dmg$/,
    );
  await page.keyboard.press("Tab");
  expect(await page.locator(":focus").count()).toBe(1);
});
test("no serious WCAG accessibility violations", async ({ page }) => {
  await page.goto("./");
  await page.emulateMedia({ reducedMotion: "reduce" });
  const result = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21aa", "wcag22aa"])
    .analyze();
  expect(result.violations).toEqual([]);
});
test("core content and download work without JavaScript", async ({
  browser,
}) => {
  const context = await browser.newContext({ javaScriptEnabled: false });
  const page = await context.newPage();
  await page.goto("http://127.0.0.1:4173/vibe-controller/");
  await expect(
    page.getByRole("heading", { name: /A few permissions/ }),
  ).toBeVisible();
  await expect(
    page.getByRole("link", { name: /^Download for Mac/ }).first(),
  ).toHaveAttribute("href", /github.com/);
  await expect(
    page.getByRole("link", { name: "See all mappings on GitHub." }),
  ).toBeVisible();
  await context.close();
});

test("mapping targets are at least 40px and never overlap", async ({
  page,
}) => {
  await page.goto("./");
  for (const width of [320, 390, 768, 1024, 1440, 1600, 1920]) {
    await page.setViewportSize({ width, height: 1000 });
    const targets = await page.locator(".hotspot").evaluateAll((buttons) =>
      buttons.map((button) => {
        const { x, y, width, height } = button.getBoundingClientRect();
        return { x, y, width, height, name: button.getAttribute("aria-label") };
      }),
    );
    for (let i = 0; i < targets.length; i++) {
      const a = targets[i];
      expect(a.width, `${width}: ${a.name} width`).toBeGreaterThanOrEqual(40);
      expect(a.height, `${width}: ${a.name} height`).toBeGreaterThanOrEqual(40);
      for (const b of targets.slice(i + 1)) {
        const intersects =
          a.x < b.x + b.width &&
          a.x + a.width > b.x &&
          a.y < b.y + b.height &&
          a.y + a.height > b.y;
        expect(intersects, `${width}: ${a.name} overlaps ${b.name}`).toBe(
          false,
        );
      }
    }
  }
});
