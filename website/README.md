# Vibe Controller marketing site

Live URL: **https://ggaabe.github.io/vibe-controller/**

Static HTML, CSS and a small JavaScript enhancement. No frontend framework, analytics, third-party fonts, cookies, visitor API calls, or gamepad/keyboard access. The build uses only Node's standard library. Development dependencies are for browser tests, accessibility checks and formatting.

## Develop and verify

Requires Node 24 or newer:

```sh
cd website
npm ci
npm run build
npx playwright install chromium
npm test
npm run serve
```

Visit `http://127.0.0.1:4173/vibe-controller/`. The preview deliberately uses the same project subpath as GitHub Pages. Override the port with `VIBE_WEBSITE_PORT` if necessary; tests expect 4173. `dist/` and test artifacts are ignored by Git.

`node build.mjs --refresh-release` resolves the latest public GitHub release at **build time**. It validates the repository, version, tag link and exact Apple-silicon DMG asset. A failed lookup stops a release-aware build, rather than publishing an unverified installer link. Offline local builds use the reviewed `release.json` snapshot; update that snapshot when appropriate. No GitHub API call is made in visitors' browsers.

## Deployment

`.github/workflows/pages.yml` builds, tests, and uploads **only `website/dist`** with GitHub's Pages actions. It runs on site changes to main, manual dispatch, manually published releases, and completion of the existing macOS release workflow. The latter handles releases created by `GITHUB_TOKEN`, which do not trigger another workflow's `release` event. It checks out main and refreshes the DMG URL after every successful release.

GitHub Pages uses the **GitHub Actions** build source. HTTPS is provided by GitHub. No app signing keys or release secrets are needed for this deployment. The existing native-app release workflow is unchanged.

The browser suite exercises desktop and mobile interactions, 320–1920px layouts, all local assets, versioned downloads, FAQ disclosure, no-JavaScript content, and axe WCAG checks. Reduced motion removes nonessential transitions and entry animations. Screenshots are manually reviewed in addition to automated checks; automated accessibility tests are not a complete accessibility audit.

## Content boundaries

- The site markets the public app, not the experimental Full USB path.
- Controller maps reuse the app's original SVG artwork, copied into `assets/` for independent deployment.
- The AI workspace and cross-Mac scene are labeled illustrations, not recordings or evidence of physical hardware behavior.
- No private phone footage, unfinished launch-demo media, or personal desktop screenshots are deployed.
- The setup section discloses Accessibility, the bundled driver, and administrator approval.
- Dictation uses the user's configured tool; TextSniper or equivalent OCR is a separate companion app.
- Remote foreground-app detection is not claimed. App-specific scopes follow the lead Mac.
- The beta is free to download and source is public. The site does not invent an open-source license for the repository.

Product details were checked against public **v0.5.5** and its release assets on 2026-09-12. References: [release](https://github.com/ggaabe/vibe-controller/releases/tag/v0.5.5), [app guide](https://github.com/ggaabe/vibe-controller#first-run-setup), [Apple Universal Control requirements](https://support.apple.com/guide/mac-help/keyboard-mouse-control-mac-ipad-mchl412faecf/mac), [GitHub Pages workflows](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).

## Artwork provenance

- `assets/icon.png`: optimized copy of the app's existing `Resources/AppIcon.png`.
- `assets/xbox.svg` and `assets/playstation.svg`: copies of `Sources/VibeController/Resources/Controllers/` artwork. Build namespacing prevents gradient ID collisions; color changes affect shell gradients only.
- `assets/hero-controller.webp`: generated with the built-in image-generation tool, then encoded to WebP (86.5 KB). It is an illustrative studio image, not a hardware product sold by Vibe Controller.
- `assets/social-card.jpg`: a 1200×630 browser-rendered crop of the site's hero for link previews.

Final image-generation prompt:

> Use case: product-mockup. Asset type: photorealistic product illustration for a Vibe Controller macOS marketing website. Create a single exquisite Xbox Series-style game controller with a saturated raspberry-pink matte front shell, black rubber analog sticks, black faceted d-pad, black colored-letter ABXY face buttons, subtly visible white lower side/back grips. Front face tilted toward the viewer, seen from slightly above at an elegant three-quarter angle, left grip nearer the camera, floating just above a surface. Precise real hardware ergonomics, two offset thumbsticks, authentic number and placement of controls. Entire controller visible with generous 12 percent space around every edge, centered, occupying 75 percent of the canvas. Warm ivory seamless studio background (#f5f3ee), soft natural contact shadow below, large softbox light, fine realistic matte plastic texture, premium industrial-design editorial product photography. Landscape 3:2 composition. No laptop, no humans, no hands, no props, no cables, no added typography, no watermarks, no UI panels. This is standalone supporting artwork, not a website screenshot.

## Design review

### Composition and product understanding

| Before                                                        | After                                                                                                                                       |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| Repository README was the landing experience                  | Full-bleed controller hero, clear brand, direct signed-DMG download, and responsive editorial sections                                      |
| No interactive explanation                                    | Three-stage capture/dictate/send demo, Xbox/PlayStation mapping explorer, shell colors, and a user-triggered three-Mac handoff illustration |
| Setup and companion requirements were buried in documentation | Three-step setup, explicit requirements and FAQ covering drivers, OCR, dictation, remote mappings and updates                               |

### Interaction, accessibility and maintainability

| Before                                                | After                                                                                                                                                                              |
| ----------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| No site navigation or accessible interaction baseline | Semantic landmarks, skip link, keyboard controls, visible focus, pressed states, live announcements, native disclosures, non-overlapping mobile mapping tray and no-JS fallback    |
| No motion system                                      | Staggered hero entry, one-time scroll reveals, subtle perspective/hover transitions and on-demand pointer movement; reduced-motion support throughout                              |
| No standalone web assets or social preview            | Optimized original app icon/SVGs, generated controller illustration and browser-rendered social card                                                                               |
| No site release process                               | Dependency-free static build, strict release-link validation, pinned Pages actions, release-aware deployment, browser/axe regression tests, formatting and local development guide |
