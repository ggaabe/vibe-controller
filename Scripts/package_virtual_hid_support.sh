#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VIBE_CONTROLLER_VERSION:-0.1.0}"
ARCHITECTURE="${VIBE_CONTROLLER_ARCH:-arm64}"
EXECUTABLE="${VIBE_CONTROLLER_HELPER_EXECUTABLE:-$ROOT_DIR/.build/release/VibeVirtualHIDBridge}"
OUTPUT="${VIBE_CONTROLLER_SUPPORT_INSTALLER_OUTPUT:-$ROOT_DIR/dist/VibeController-VirtualHardwareSupport.pkg}"
PACKAGE_RESOURCES="$ROOT_DIR/Scripts/VirtualHIDSupportPackage"
HELPER_SCRIPTS="$PACKAGE_RESOURCES/HelperScripts"
DRIVER_PACKAGE="${KARABINER_VIRTUAL_HID_PKG:-$ROOT_DIR/.build/downloads/Karabiner-DriverKit-VirtualHIDDevice-8.2.0.pkg}"
SIGNING_IDENTITY="${VIBE_CONTROLLER_SIGNING_IDENTITY:-}"
INSTALLER_SIGNING_IDENTITY="${VIBE_CONTROLLER_INSTALLER_SIGNING_IDENTITY:-}"
REQUIRE_DISTRIBUTION_SIGNING="${VIBE_CONTROLLER_REQUIRE_DISTRIBUTION_SIGNING:-0}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VIBE_CONTROLLER_VERSION must use three numeric components (for example, 1.2.3): $VERSION"
  exit 1
fi

if [[ "$ARCHITECTURE" != "arm64" ]]; then
  echo "Virtual Hardware Support currently supports Apple silicon only: $ARCHITECTURE"
  exit 1
fi

if [[ "$REQUIRE_DISTRIBUTION_SIGNING" != "0" && "$REQUIRE_DISTRIBUTION_SIGNING" != "1" ]]; then
  echo "VIBE_CONTROLLER_REQUIRE_DISTRIBUTION_SIGNING must be 0 or 1."
  exit 1
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  if [[ "$REQUIRE_DISTRIBUTION_SIGNING" == "1" ]]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning \
      | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' \
      | head -n 1)"
  else
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning \
      | sed -n 's/.*"\(.*\)"/\1/p' \
      | head -n 1)"
  fi
fi

if [[ -z "$INSTALLER_SIGNING_IDENTITY" && "$REQUIRE_DISTRIBUTION_SIGNING" == "1" ]]; then
  INSTALLER_SIGNING_IDENTITY="$(security find-identity -v -p basic \
    | sed -n 's/.*"\(Developer ID Installer:.*\)"/\1/p' \
    | head -n 1)"
fi

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Missing release helper at $EXECUTABLE"
  echo "Run: swift build -c release --arch arm64 --product VibeVirtualHIDBridge"
  exit 1
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "No code-signing identity is available. Set VIBE_CONTROLLER_SIGNING_IDENTITY."
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -Fq "\"$SIGNING_IDENTITY\""; then
  echo "Configured signing identity not found: $SIGNING_IDENTITY"
  exit 1
fi

if [[ "$REQUIRE_DISTRIBUTION_SIGNING" == "1" && "$SIGNING_IDENTITY" != Developer\ ID\ Application:* ]]; then
  echo "Public releases require a Developer ID Application identity, not: $SIGNING_IDENTITY"
  exit 1
fi

if [[ "$REQUIRE_DISTRIBUTION_SIGNING" == "1" && "$INSTALLER_SIGNING_IDENTITY" != Developer\ ID\ Installer:* ]]; then
  echo "Public releases require VIBE_CONTROLLER_INSTALLER_SIGNING_IDENTITY to be a Developer ID Installer identity."
  exit 1
fi

if [[ -n "$INSTALLER_SIGNING_IDENTITY" ]] \
  && ! security find-identity -v -p basic | grep -Fq "\"$INSTALLER_SIGNING_IDENTITY\""; then
  echo "Configured installer signing identity not found: $INSTALLER_SIGNING_IDENTITY"
  exit 1
fi

WORK_DIR="$(mktemp -d /tmp/vibe-controller-virtual-hid-support.XXXXXX)"
PAYLOAD_DIR="$WORK_DIR/root"
HELPER_DIR="$PAYLOAD_DIR/Library/PrivilegedHelperTools"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$HELPER_DIR" "$(dirname "$OUTPUT")"

install -m 755 "$EXECUTABLE" "$HELPER_DIR/com.vibe-controller.virtual-hid-bridge"
HELPER_CODESIGN_ARGUMENTS=(
  --force
  --sign "$SIGNING_IDENTITY"
  --identifier com.vibe-controller.virtual-hid-bridge
)
if [[ "$REQUIRE_DISTRIBUTION_SIGNING" == "1" ]]; then
  HELPER_CODESIGN_ARGUMENTS+=(--options runtime --timestamp)
fi
codesign \
  "${HELPER_CODESIGN_ARGUMENTS[@]}" \
  "$HELPER_DIR/com.vibe-controller.virtual-hid-bridge"
codesign \
  --verify \
  --strict \
  --verbose=2 \
  "$HELPER_DIR/com.vibe-controller.virtual-hid-bridge"

HELPER_PACKAGE="$WORK_DIR/VibeController-Helper.pkg"
pkgbuild \
  --root "$PAYLOAD_DIR" \
  --scripts "$HELPER_SCRIPTS" \
  --identifier com.vibe-controller.virtual-hardware-support \
  --version "$VERSION" \
  --install-location / \
  "$HELPER_PACKAGE"

if [[ ! -f "$DRIVER_PACKAGE" ]]; then
  echo "Missing the pinned Karabiner virtual HID package at $DRIVER_PACKAGE"
  echo "Run Scripts/fetch_virtual_hid_driver.sh first."
  exit 1
fi

pkgutil --check-signature "$DRIVER_PACKAGE" \
  | grep -Fq "Notarization: trusted by the Apple notary service"
install -m 644 \
  "$DRIVER_PACKAGE" \
  "$WORK_DIR/Karabiner-DriverKit-VirtualHIDDevice-8.2.0.pkg"

DISTRIBUTION_FILE="$WORK_DIR/Distribution.xml"
sed \
  "s/__VIBE_CONTROLLER_VERSION__/$VERSION/g" \
  "$PACKAGE_RESOURCES/Distribution.xml" \
  > "$DISTRIBUTION_FILE"

PRODUCTBUILD_ARGUMENTS=(
  --distribution "$DISTRIBUTION_FILE"
  --package-path "$WORK_DIR"
)
if [[ -n "$INSTALLER_SIGNING_IDENTITY" ]]; then
  PRODUCTBUILD_ARGUMENTS+=(--sign "$INSTALLER_SIGNING_IDENTITY")
fi

productbuild "${PRODUCTBUILD_ARGUMENTS[@]}" "$OUTPUT"

if [[ -n "$INSTALLER_SIGNING_IDENTITY" ]]; then
  pkgutil --check-signature "$OUTPUT"
else
  echo "Built an unsigned local-development installer. Set VIBE_CONTROLLER_INSTALLER_SIGNING_IDENTITY to sign a distributable package."
fi

echo "Packaged $OUTPUT (version $VERSION, $ARCHITECTURE)"
