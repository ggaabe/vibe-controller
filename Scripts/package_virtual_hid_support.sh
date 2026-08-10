#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
EXECUTABLE="$ROOT_DIR/.build/release/VibeVirtualHIDBridge"
OUTPUT="$ROOT_DIR/dist/VibeController-VirtualHardwareSupport-0.1.0.pkg"
PACKAGE_RESOURCES="$ROOT_DIR/Scripts/VirtualHIDSupportPackage"
HELPER_SCRIPTS="$PACKAGE_RESOURCES/HelperScripts"
DRIVER_PACKAGE="${KARABINER_VIRTUAL_HID_PKG:-$ROOT_DIR/.build/downloads/Karabiner-DriverKit-VirtualHIDDevice-8.2.0.pkg}"
SIGNING_IDENTITY="${VIBE_CONTROLLER_SIGNING_IDENTITY:-}"
INSTALLER_SIGNING_IDENTITY="${VIBE_CONTROLLER_INSTALLER_SIGNING_IDENTITY:-}"

if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(.*\)"/\1/p' | head -n 1)"
fi

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Missing release helper at $EXECUTABLE"
  echo "Run: swift build -c release --product VibeVirtualHIDBridge"
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
  --scripts "$HELPER_SCRIPTS" \
  --identifier com.vibe-controller.virtual-hardware-support \
  --version 0.1.0 \
  --install-location / \
  "$HELPER_PACKAGE"

if [[ ! -f "$DRIVER_PACKAGE" ]]; then
  echo "Missing the pinned Karabiner virtual HID package at $DRIVER_PACKAGE"
  echo "Run Scripts/fetch_virtual_hid_driver.sh first."
  exit 1
fi

pkgutil --check-signature "$DRIVER_PACKAGE" | grep -Fq "Notarization: trusted by the Apple notary service"
cp "$DRIVER_PACKAGE" "$WORK_DIR/Karabiner-DriverKit-VirtualHIDDevice-8.2.0.pkg"

PRODUCTBUILD_ARGUMENTS=(
  --distribution "$PACKAGE_RESOURCES/Distribution.xml"
  --package-path "$WORK_DIR"
)
if [[ -n "$INSTALLER_SIGNING_IDENTITY" ]]; then
  if ! security find-identity -v -p basic | grep -Fq "\"$INSTALLER_SIGNING_IDENTITY\""; then
    echo "Configured installer signing identity not found: $INSTALLER_SIGNING_IDENTITY"
    exit 1
  fi
  PRODUCTBUILD_ARGUMENTS+=(--sign "$INSTALLER_SIGNING_IDENTITY")
fi

productbuild "${PRODUCTBUILD_ARGUMENTS[@]}" "$OUTPUT"

if [[ -n "$INSTALLER_SIGNING_IDENTITY" ]]; then
  pkgutil --check-signature "$OUTPUT"
else
  echo "Built an unsigned local-development installer. Set VIBE_CONTROLLER_INSTALLER_SIGNING_IDENTITY to sign a distributable package."
fi

echo "Packaged $OUTPUT"
