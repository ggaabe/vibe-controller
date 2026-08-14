#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VIBE_CONTROLLER_VERSION:-0.1.0}"
BUILD_NUMBER="${VIBE_CONTROLLER_BUILD_NUMBER:-1}"
BUILD_CONFIGURATION="${VIBE_CONTROLLER_BUILD_CONFIGURATION:-debug}"
ARCHITECTURE="${VIBE_CONTROLLER_ARCH:-arm64}"
SUPPORT_INSTALLER="${VIBE_CONTROLLER_SUPPORT_INSTALLER_PATH:-}"
SIGNING_IDENTITY="${VIBE_CONTROLLER_SIGNING_IDENTITY:-}"
REQUIRE_DISTRIBUTION_SIGNING="${VIBE_CONTROLLER_REQUIRE_DISTRIBUTION_SIGNING:-0}"
DEFAULT_SIGNING_IDENTITY="Apple Development: Gabriel Garrett (Q527MSL34N)"
PRODUCTION_BUNDLE_IDENTIFIER="com.vibe-controller.app"

if [[ "$REQUIRE_DISTRIBUTION_SIGNING" == "1" ]]; then
  DEFAULT_APP_NAME="Vibe Controller"
  DEFAULT_BUNDLE_IDENTIFIER="$PRODUCTION_BUNDLE_IDENTIFIER"
else
  DEFAULT_APP_NAME="Vibe Controller Dev"
  DEFAULT_BUNDLE_IDENTIFIER="com.vibe-controller.app.dev"
fi

APP_NAME="${VIBE_CONTROLLER_APP_NAME:-$DEFAULT_APP_NAME}"
BUNDLE_IDENTIFIER="${VIBE_CONTROLLER_BUNDLE_IDENTIFIER:-$DEFAULT_BUNDLE_IDENTIFIER}"
APP_DIR="${VIBE_CONTROLLER_APP_OUTPUT:-$ROOT_DIR/dist/$APP_NAME.app}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VIBE_CONTROLLER_VERSION must use three numeric components (for example, 1.2.3): $VERSION"
  exit 1
fi

if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "VIBE_CONTROLLER_BUILD_NUMBER must be a positive integer: $BUILD_NUMBER"
  exit 1
fi

if [[ "$BUILD_CONFIGURATION" != "debug" && "$BUILD_CONFIGURATION" != "release" ]]; then
  echo "VIBE_CONTROLLER_BUILD_CONFIGURATION must be debug or release: $BUILD_CONFIGURATION"
  exit 1
fi

if [[ "$ARCHITECTURE" != "arm64" ]]; then
  echo "Vibe Controller currently packages Apple-silicon builds only. Unsupported architecture: $ARCHITECTURE"
  exit 1
fi

if [[ "$REQUIRE_DISTRIBUTION_SIGNING" != "0" && "$REQUIRE_DISTRIBUTION_SIGNING" != "1" ]]; then
  echo "VIBE_CONTROLLER_REQUIRE_DISTRIBUTION_SIGNING must be 0 or 1."
  exit 1
fi

if [[ "$REQUIRE_DISTRIBUTION_SIGNING" == "1" \
  && ( "$APP_NAME" != "Vibe Controller" || "$BUNDLE_IDENTIFIER" != "$PRODUCTION_BUNDLE_IDENTIFIER" ) ]]; then
  echo "Public releases must use the production app name and bundle identifier."
  exit 1
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  if [[ "$REQUIRE_DISTRIBUTION_SIGNING" == "1" ]]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning \
      | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' \
      | head -n 1)"
  elif security find-identity -v -p codesigning | grep -Fq "\"$DEFAULT_SIGNING_IDENTITY\""; then
    SIGNING_IDENTITY="$DEFAULT_SIGNING_IDENTITY"
  else
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning \
      | sed -n 's/.*"\(.*\)"/\1/p' \
      | head -n 1)"
  fi
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  if [[ "$REQUIRE_DISTRIBUTION_SIGNING" == "1" ]]; then
    echo "No Developer ID Application signing identity was found."
  else
    echo "No Apple code-signing identity was found."
  fi
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -Fq "\"$SIGNING_IDENTITY\""; then
  echo "Configured signing identity not found: $SIGNING_IDENTITY"
  echo "Set VIBE_CONTROLLER_SIGNING_IDENTITY to one of the identities returned by:"
  echo "  security find-identity -v -p codesigning"
  exit 1
fi

if [[ "$REQUIRE_DISTRIBUTION_SIGNING" == "1" && "$SIGNING_IDENTITY" != Developer\ ID\ Application:* ]]; then
  echo "Public releases require a Developer ID Application identity, not: $SIGNING_IDENTITY"
  exit 1
fi

swift build \
  --package-path "$ROOT_DIR" \
  -c "$BUILD_CONFIGURATION" \
  --arch "$ARCHITECTURE" \
  --product VibeController

BIN_DIR="$(swift build \
  --package-path "$ROOT_DIR" \
  -c "$BUILD_CONFIGURATION" \
  --arch "$ARCHITECTURE" \
  --show-bin-path)"
EXECUTABLE="$BIN_DIR/VibeController"

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "The Vibe Controller build did not produce $EXECUTABLE"
  exit 1
fi

if [[ -z "$SUPPORT_INSTALLER" ]]; then
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
  SUPPORT_INSTALLER="$ROOT_DIR/dist/VibeController-VirtualHardwareSupport.pkg"
  VIBE_CONTROLLER_VERSION="$VERSION" \
  VIBE_CONTROLLER_ARCH="$ARCHITECTURE" \
  VIBE_CONTROLLER_HELPER_EXECUTABLE="$HELPER_BIN_DIR/VibeVirtualHIDBridge" \
  VIBE_CONTROLLER_SUPPORT_INSTALLER_OUTPUT="$SUPPORT_INSTALLER" \
  VIBE_CONTROLLER_SIGNING_IDENTITY="$SIGNING_IDENTITY" \
  VIBE_CONTROLLER_REQUIRE_DISTRIBUTION_SIGNING="$REQUIRE_DISTRIBUTION_SIGNING" \
    "$ROOT_DIR/Scripts/package_virtual_hid_support.sh"
fi

if [[ ! -f "$SUPPORT_INSTALLER" ]]; then
  echo "Missing Virtual Hardware Support installer at $SUPPORT_INSTALLER"
  exit 1
fi

APP_PARENT="$(dirname "$APP_DIR")"
mkdir -p "$APP_PARENT"
WORK_DIR="$(mktemp -d "$APP_PARENT/.vibe-controller-app.XXXXXX")"
STAGED_APP="$WORK_DIR/$APP_NAME.app"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
install -m 755 "$EXECUTABLE" "$STAGED_APP/Contents/MacOS/VibeController"
install -m 644 \
  "$SUPPORT_INSTALLER" \
  "$STAGED_APP/Contents/Resources/VibeController-VirtualHardwareSupport.pkg"
install -m 644 \
  "$ROOT_DIR/THIRD_PARTY_NOTICES.md" \
  "$STAGED_APP/Contents/Resources/THIRD_PARTY_NOTICES.md"

APP_ICON="$ROOT_DIR/Resources/AppIcon.icns"
if [[ ! -f "$APP_ICON" ]]; then
  echo "Missing app icon at $APP_ICON"
  exit 1
fi
install -m 644 "$APP_ICON" "$STAGED_APP/Contents/Resources/AppIcon.icns"

cat > "$STAGED_APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>VibeController</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_IDENTIFIER</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSBonjourServices</key>
  <array>
    <string>_vibectl._tcp</string>
  </array>
  <key>NSAppleEventsUsageDescription</key>
  <string>$APP_NAME uses System Events to trigger Mission Control and Space-switching shortcuts.</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSLocalNetworkUsageDescription</key>
  <string>$APP_NAME uses the local network to forward pointer and shortcut events between your Macs.</string>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF

plutil -lint "$STAGED_APP/Contents/Info.plist"

CODESIGN_ARGUMENTS=(
  --force
  --deep
  --sign "$SIGNING_IDENTITY"
)
if [[ "$REQUIRE_DISTRIBUTION_SIGNING" == "1" ]]; then
  CODESIGN_ARGUMENTS+=(--options runtime --timestamp)
fi

codesign "${CODESIGN_ARGUMENTS[@]}" "$STAGED_APP"
codesign --verify --deep --strict --verbose=2 "$STAGED_APP"

rm -rf "$APP_DIR"
mv "$STAGED_APP" "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "Packaged $APP_DIR (version $VERSION, build $BUILD_NUMBER, $BUNDLE_IDENTIFIER, $ARCHITECTURE/$BUILD_CONFIGURATION)"
