#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/Vibe Controller.app"
EXECUTABLE="$ROOT_DIR/.build/debug/VibeController"
SIGNING_IDENTITY="${VIBE_CONTROLLER_SIGNING_IDENTITY:-}"
DEFAULT_SIGNING_IDENTITY="Apple Development: Gabriel Garrett (Q527MSL34N)"

if [[ -z "$SIGNING_IDENTITY" ]]; then
  if security find-identity -v -p codesigning | grep -Fq "\"$DEFAULT_SIGNING_IDENTITY\""; then
    SIGNING_IDENTITY="$DEFAULT_SIGNING_IDENTITY"
  else
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(.*\)"/\1/p' | head -n 1)"
  fi
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "No Apple Development signing identity found."
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -Fq "\"$SIGNING_IDENTITY\""; then
  echo "Configured signing identity not found: $SIGNING_IDENTITY"
  echo "Set VIBE_CONTROLLER_SIGNING_IDENTITY to one of the identities returned by:"
  echo "  security find-identity -v -p codesigning"
  exit 1
fi

export VIBE_CONTROLLER_SIGNING_IDENTITY="$SIGNING_IDENTITY"
swift build --package-path "$ROOT_DIR" --product VibeController
swift build --package-path "$ROOT_DIR" -c release --product VibeVirtualHIDBridge
"$ROOT_DIR/Scripts/fetch_virtual_hid_driver.sh"
"$ROOT_DIR/Scripts/package_virtual_hid_support.sh"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/VibeController"

SUPPORT_INSTALLER="$ROOT_DIR/dist/VibeController-VirtualHardwareSupport-0.1.0.pkg"
if [[ ! -f "$SUPPORT_INSTALLER" ]]; then
  echo "Virtual Hardware Support packaging did not produce $SUPPORT_INSTALLER"
  exit 1
fi
cp "$SUPPORT_INSTALLER" "$APP_DIR/Contents/Resources/"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$APP_DIR/Contents/Resources/"

cat > "$APP_DIR/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>VibeController</string>
  <key>CFBundleIdentifier</key>
  <string>com.vibe-controller.app</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Vibe Controller</string>
  <key>CFBundleDisplayName</key>
  <string>Vibe Controller</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSBonjourServices</key>
  <array>
    <string>_vibectl._tcp</string>
  </array>
  <key>NSAppleEventsUsageDescription</key>
  <string>Vibe Controller uses System Events to trigger Mission Control and Space-switching shortcuts.</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSLocalNetworkUsageDescription</key>
  <string>Vibe Controller uses the local network to forward pointer and shortcut events between your Macs.</string>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF

codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_DIR"
echo "Packaged $APP_DIR"
