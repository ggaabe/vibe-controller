#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-${VIBE_CONTROLLER_VERSION:-0.1.0}}"
BUILD_NUMBER="${VIBE_CONTROLLER_BUILD_NUMBER:-1}"
ARCHITECTURE="${VIBE_CONTROLLER_ARCH:-arm64}"
RELEASE_MODE="${VIBE_CONTROLLER_RELEASE_MODE:-development}"
RELEASE_DIR="${VIBE_CONTROLLER_RELEASE_OUTPUT_DIR:-$ROOT_DIR/dist/release}"

if [[ "$RELEASE_DIR" != /* ]]; then
  RELEASE_DIR="$ROOT_DIR/$RELEASE_DIR"
fi

if [[ "$RELEASE_DIR" == "/" || "$RELEASE_DIR" == "$ROOT_DIR" || "$RELEASE_DIR" == "$ROOT_DIR/" ]]; then
  echo "Refusing to use an unsafe release output directory: $RELEASE_DIR"
  exit 1
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Release version must use three numeric components (for example, 1.2.3): $VERSION"
  exit 1
fi

if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "VIBE_CONTROLLER_BUILD_NUMBER must be a positive integer: $BUILD_NUMBER"
  exit 1
fi

if [[ "$ARCHITECTURE" != "arm64" ]]; then
  echo "Vibe Controller releases currently support Apple silicon only: $ARCHITECTURE"
  exit 1
fi

if [[ "$RELEASE_MODE" != "development" && "$RELEASE_MODE" != "distribution" ]]; then
  echo "VIBE_CONTROLLER_RELEASE_MODE must be development or distribution: $RELEASE_MODE"
  exit 1
fi

if [[ "$RELEASE_MODE" == "distribution" ]]; then
  ARTIFACT_SUFFIX=""
  REQUIRE_DISTRIBUTION_SIGNING=1
  APP_NAME="Vibe Controller"
  BUNDLE_IDENTIFIER="com.vibe-controller.app"
else
  ARTIFACT_SUFFIX="-development"
  REQUIRE_DISTRIBUTION_SIGNING=0
  APP_NAME="Vibe Controller Dev"
  BUNDLE_IDENTIFIER="com.vibe-controller.app.dev"
fi

APP_PATH="$RELEASE_DIR/$APP_NAME.app"
SUPPORT_INSTALLER="$RELEASE_DIR/VibeController-VirtualHardwareSupport-$VERSION-$ARCHITECTURE$ARTIFACT_SUFFIX.pkg"
DMG_PATH="$RELEASE_DIR/Vibe-Controller-$VERSION-$ARCHITECTURE$ARTIFACT_SUFFIX.dmg"
CHECKSUM_PATH="$RELEASE_DIR/SHA256SUMS.txt"

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"
WORK_DIR="$(mktemp -d "$RELEASE_DIR/.build-release.XXXXXX")"
MOUNT_DIR="$WORK_DIR/mount"
DMG_SOURCE="$WORK_DIR/dmg"
IS_MOUNTED=0

cleanup() {
  if [[ "$IS_MOUNTED" == "1" ]]; then
    hdiutil detach "$MOUNT_DIR" -quiet || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

NOTARY_ARGUMENTS=()
if [[ "$RELEASE_MODE" == "distribution" ]]; then
  if [[ -n "${VIBE_CONTROLLER_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    NOTARY_ARGUMENTS=(
      --keychain-profile "$VIBE_CONTROLLER_NOTARY_KEYCHAIN_PROFILE"
    )
  elif [[ -n "${VIBE_CONTROLLER_NOTARY_KEY_PATH:-}" \
    && -n "${VIBE_CONTROLLER_NOTARY_KEY_ID:-}" \
    && -n "${VIBE_CONTROLLER_NOTARY_ISSUER_ID:-}" ]]; then
    NOTARY_ARGUMENTS=(
      --key "$VIBE_CONTROLLER_NOTARY_KEY_PATH"
      --key-id "$VIBE_CONTROLLER_NOTARY_KEY_ID"
      --issuer "$VIBE_CONTROLLER_NOTARY_ISSUER_ID"
    )
  else
    echo "Distribution releases require notarization credentials."
    echo "Set VIBE_CONTROLLER_NOTARY_KEYCHAIN_PROFILE, or set all of:"
    echo "  VIBE_CONTROLLER_NOTARY_KEY_PATH"
    echo "  VIBE_CONTROLLER_NOTARY_KEY_ID"
    echo "  VIBE_CONTROLLER_NOTARY_ISSUER_ID"
    exit 1
  fi
fi

notarize() {
  local artifact="$1"
  xcrun notarytool submit \
    "$artifact" \
    "${NOTARY_ARGUMENTS[@]}" \
    --wait \
    --timeout 30m
}

echo "Running the Vibe Controller test suite..."
swift test --package-path "$ROOT_DIR"

echo "Building Virtual Hardware Support..."
swift build \
  --package-path "$ROOT_DIR" \
  -c release \
  --arch "$ARCHITECTURE" \
  --product VibeVirtualHIDBridge
HELPER_BIN_DIR="$(swift build \
  --package-path "$ROOT_DIR" \
  -c release \
  --arch "$ARCHITECTURE" \
  --show-bin-path)"
"$ROOT_DIR/Scripts/fetch_virtual_hid_driver.sh"

VIBE_CONTROLLER_VERSION="$VERSION" \
VIBE_CONTROLLER_ARCH="$ARCHITECTURE" \
VIBE_CONTROLLER_HELPER_EXECUTABLE="$HELPER_BIN_DIR/VibeVirtualHIDBridge" \
VIBE_CONTROLLER_SUPPORT_INSTALLER_OUTPUT="$SUPPORT_INSTALLER" \
VIBE_CONTROLLER_REQUIRE_DISTRIBUTION_SIGNING="$REQUIRE_DISTRIBUTION_SIGNING" \
  "$ROOT_DIR/Scripts/package_virtual_hid_support.sh"

if [[ "$RELEASE_MODE" == "distribution" ]]; then
  echo "Notarizing Virtual Hardware Support..."
  notarize "$SUPPORT_INSTALLER"
  xcrun stapler staple -v "$SUPPORT_INSTALLER"
  xcrun stapler validate -v "$SUPPORT_INSTALLER"
  spctl --assess --type install --verbose=4 "$SUPPORT_INSTALLER"
else
  install -m 644 \
    "$SUPPORT_INSTALLER" \
    "$ROOT_DIR/dist/VibeController-VirtualHardwareSupport.pkg"
fi

echo "Building the release app..."
VIBE_CONTROLLER_VERSION="$VERSION" \
VIBE_CONTROLLER_BUILD_NUMBER="$BUILD_NUMBER" \
VIBE_CONTROLLER_BUILD_CONFIGURATION=release \
VIBE_CONTROLLER_ARCH="$ARCHITECTURE" \
VIBE_CONTROLLER_APP_OUTPUT="$APP_PATH" \
VIBE_CONTROLLER_APP_NAME="$APP_NAME" \
VIBE_CONTROLLER_BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
VIBE_CONTROLLER_SUPPORT_INSTALLER_PATH="$SUPPORT_INSTALLER" \
VIBE_CONTROLLER_REQUIRE_DISTRIBUTION_SIGNING="$REQUIRE_DISTRIBUTION_SIGNING" \
  "$ROOT_DIR/Scripts/package_app.sh"

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")" == "$VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")" == "$BUILD_NUMBER" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")" == "$BUNDLE_IDENTIFIER" ]]
file "$APP_PATH/Contents/MacOS/VibeController" | grep -Fq "arm64"
cmp \
  "$SUPPORT_INSTALLER" \
  "$APP_PATH/Contents/Resources/VibeController-VirtualHardwareSupport.pkg"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

if [[ "$RELEASE_MODE" == "distribution" ]]; then
  echo "Notarizing the app..."
  APP_ARCHIVE="$WORK_DIR/Vibe-Controller-$VERSION-$ARCHITECTURE.zip"
  ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$APP_ARCHIVE"
  notarize "$APP_ARCHIVE"
  xcrun stapler staple -v "$APP_PATH"
  xcrun stapler validate -v "$APP_PATH"
  spctl --assess --type execute --verbose=4 "$APP_PATH"
fi

echo "Creating the disk image..."
mkdir -p "$DMG_SOURCE" "$MOUNT_DIR"
ditto "$APP_PATH" "$DMG_SOURCE/$APP_NAME.app"
ln -s /Applications "$DMG_SOURCE/Applications"
hdiutil create \
  -volname "Vibe Controller" \
  -srcfolder "$DMG_SOURCE" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$DMG_PATH"

if [[ "$RELEASE_MODE" == "distribution" ]]; then
  echo "Signing and notarizing the disk image..."
  codesign \
    --force \
    --timestamp \
    --sign "$VIBE_CONTROLLER_SIGNING_IDENTITY" \
    "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
  notarize "$DMG_PATH"
  xcrun stapler staple -v "$DMG_PATH"
  xcrun stapler validate -v "$DMG_PATH"
  spctl \
    --assess \
    --type open \
    --context context:primary-signature \
    --verbose=4 \
    "$DMG_PATH"
fi

hdiutil verify "$DMG_PATH"
hdiutil attach \
  "$DMG_PATH" \
  -nobrowse \
  -readonly \
  -mountpoint "$MOUNT_DIR" \
  -quiet
IS_MOUNTED=1

if [[ ! -d "$MOUNT_DIR/$APP_NAME.app" ]]; then
  echo "The disk image does not contain $APP_NAME.app."
  exit 1
fi
if [[ ! -L "$MOUNT_DIR/Applications" \
  || "$(readlink "$MOUNT_DIR/Applications")" != "/Applications" ]]; then
  echo "The disk image does not contain the Applications shortcut."
  exit 1
fi
codesign \
  --verify \
  --deep \
  --strict \
  --verbose=2 \
  "$MOUNT_DIR/$APP_NAME.app"
hdiutil detach "$MOUNT_DIR" -quiet
IS_MOUNTED=0

(
  cd "$RELEASE_DIR"
  shasum -a 256 \
    "$(basename "$DMG_PATH")" \
    "$(basename "$SUPPORT_INSTALLER")" \
    > "$(basename "$CHECKSUM_PATH")"
)

if [[ "$RELEASE_MODE" == "development" ]]; then
  echo "Created local-development artifacts. They are not notarized and must not be published as a public release."
fi
echo "Release artifacts:"
echo "  $DMG_PATH"
echo "  $SUPPORT_INSTALLER"
echo "  $CHECKSUM_PATH"
