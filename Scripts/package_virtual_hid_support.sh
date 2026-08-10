#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
EXECUTABLE="$ROOT_DIR/.build/release/VibeVirtualHIDBridge"
OUTPUT="$ROOT_DIR/dist/VibeController-VirtualHardwareSupport-0.1.0.pkg"
PACKAGE_SCRIPTS="$ROOT_DIR/Scripts/VirtualHIDSupportPackage"
DRIVER_PACKAGE="${KARABINER_VIRTUAL_HID_PKG:-$ROOT_DIR/.build/downloads/Karabiner-DriverKit-VirtualHIDDevice-8.2.0.pkg}"
SIGNING_IDENTITY="${VIBE_CONTROLLER_SIGNING_IDENTITY:-Apple Development: Gabriel Garrett (Q527MSL34N)}"

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Missing release helper at $EXECUTABLE"
  echo "Run: swift build -c release --product VibeVirtualHIDBridge"
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -Fq "\"$SIGNING_IDENTITY\""; then
  echo "Configured signing identity not found: $SIGNING_IDENTITY"
  exit 1
fi

WORK_DIR="$(mktemp -d /tmp/vibe-controller-virtual-hid-support.XXXXXX)"
PAYLOAD_DIR="$WORK_DIR/root"
HELPER_DIR="$PAYLOAD_DIR/Library/PrivilegedHelperTools"
mkdir -p "$HELPER_DIR" "$ROOT_DIR/dist"

cp "$EXECUTABLE" "$HELPER_DIR/com.vibe-controller.virtual-hid-bridge"
codesign \
  --force \
  --sign "$SIGNING_IDENTITY" \
  --identifier com.vibe-controller.virtual-hid-bridge \
  "$HELPER_DIR/com.vibe-controller.virtual-hid-bridge"

HELPER_PACKAGE="$WORK_DIR/VibeController-Helper.pkg"
pkgbuild \
  --root "$PAYLOAD_DIR" \
  --scripts "$PACKAGE_SCRIPTS" \
  --identifier com.vibe-controller.virtual-hardware-support \
  --version 0.1.0 \
  --install-location / \
  "$HELPER_PACKAGE"

if [[ -f "$DRIVER_PACKAGE" ]]; then
  pkgutil --check-signature "$DRIVER_PACKAGE" | grep -Fq "Notarization: trusted by the Apple notary service"
  cp "$DRIVER_PACKAGE" "$WORK_DIR/Karabiner-DriverKit-VirtualHIDDevice-8.2.0.pkg"
  productbuild \
    --distribution "$PACKAGE_SCRIPTS/Distribution.xml" \
    --package-path "$WORK_DIR" \
    "$OUTPUT"
else
  cp "$HELPER_PACKAGE" "$OUTPUT"
  echo "Warning: packaged only the Vibe helper because the Karabiner driver package was not found."
  echo "Run Scripts/fetch_virtual_hid_driver.sh, then package again for a combined installer."
fi

echo "Packaged $OUTPUT"
