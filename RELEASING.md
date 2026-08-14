# Releasing Vibe Controller

Vibe Controller's release workflow builds an Apple-silicon app, signs the app and privileged bridge, signs the Virtual Hardware Support installer, notarizes every public artifact with Apple, verifies Gatekeeper acceptance, creates a drag-to-Applications DMG, and publishes the DMG, standalone support installer, and SHA-256 checksums to GitHub Releases.

Public artifacts are never produced with development signatures. A missing certificate, notarization credential, rejected signature, failed test, malformed tag, or failed mounted-DMG check stops the workflow before the GitHub Release is created.

The in-app updater reads GitHub's latest stable release and expects the workflow's existing `Vibe-Controller-<version>-arm64.dmg` and `SHA256SUMS.txt` asset names. Do not rename or omit those assets. Before replacing the installed app, the updater verifies the published checksum, Gatekeeper acceptance, the embedded version, the production bundle identifier, and the current app's Developer ID designated requirement.

## One-time Apple setup

An Apple Developer Program team must provide:

1. A **Developer ID Application** certificate and private key, exported from Keychain Access as a password-protected `.p12`. This signs the app, bridge, and DMG.
2. A **Developer ID Installer** certificate and private key, exported as a separate password-protected `.p12`. This signs Virtual Hardware Support.
3. An App Store Connect API key authorized for notarization, including its `.p8` file, key ID, and issuer ID.

Add the following repository Actions secrets in **GitHub → Settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_APPLICATION_P12_BASE64` | Base64-encoded Developer ID Application `.p12` |
| `DEVELOPER_ID_APPLICATION_P12_PASSWORD` | Password used when exporting that `.p12` |
| `DEVELOPER_ID_INSTALLER_P12_BASE64` | Base64-encoded Developer ID Installer `.p12` |
| `DEVELOPER_ID_INSTALLER_P12_PASSWORD` | Password used when exporting that `.p12` |
| `APP_STORE_CONNECT_API_KEY_P8_BASE64` | Base64-encoded App Store Connect `.p8` key |
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect API key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect API issuer ID |

Encode binary credentials without committing them:

```sh
base64 -i DeveloperIDApplication.p12 | pbcopy
base64 -i DeveloperIDInstaller.p12 | pbcopy
base64 -i AuthKey_EXAMPLE.p8 | pbcopy
```

Paste each clipboard value into its matching GitHub secret. Keep the original files out of the repository. The workflow imports them into an ephemeral keychain and removes the temporary files after every run.

## Validate packaging locally

Any contributor with an Apple Development certificate can exercise the whole non-public packaging path:

```sh
./Scripts/build_release.sh 0.1.0
```

This runs the test suite, builds the app and combined support installer, makes and mounts a DMG, verifies its contents and signatures, and writes checksums under `dist/release/`. Its filenames end in `-development`; those artifacts are deliberately not notarized and must not be uploaded as a public release.

The development disk image contains **Vibe Controller Dev.app** with bundle identifier `com.vibe-controller.app.dev`. Distribution releases contain **Vibe Controller.app** with `com.vibe-controller.app`. Keeping those identities separate prevents local development builds from replacing the public app's Accessibility approval.

Maintainers can run the distribution path locally with Developer ID identities and either an existing `notarytool` keychain profile or App Store Connect key environment variables:

```sh
VIBE_CONTROLLER_RELEASE_MODE=distribution \
VIBE_CONTROLLER_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
VIBE_CONTROLLER_INSTALLER_SIGNING_IDENTITY="Developer ID Installer: Your Name (TEAMID)" \
VIBE_CONTROLLER_NOTARY_KEYCHAIN_PROFILE="vibe-controller-notary" \
./Scripts/build_release.sh 0.1.0
```

## Publish a release

1. Update and test `main`.
2. Choose a three-part version such as `0.1.0`.
3. Create and push an annotated `v` tag:

   ```sh
   git tag -a v0.1.0 -m "Vibe Controller 0.1.0"
   git push origin v0.1.0
   ```

4. Watch **Publish macOS release** in GitHub Actions. The release appears only after Apple notarization and all local validation succeeds.
5. Download the published DMG on a clean Mac, drag Vibe Controller to Applications, open it, and complete the normal Accessibility and Virtual Hardware Support prompts.

Re-running a failed tag is safe before a GitHub Release exists. If a source change is required, delete the remote tag, create a new commit, recreate the tag on that commit, and push it again. Never move a tag that already has a published release; publish a new patch version instead.

## Architecture

The current app and bundled Karabiner DriverKit package are released for Apple silicon (`arm64`) and require macOS 14 or newer. The workflow runs on GitHub's Apple-silicon `macos-26` runner so it can execute the exact binaries it validates.
