#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:?Usage: package_xbox_usb_session.sh staged.app}"
IDENTITY="${VIBE_CONTROLLER_SIGNING_IDENTITY:?Missing signing identity}"
APP_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
if [[ "$APP_ID" != com.vibe-controller.app.dev || "${VIBE_CONTROLLER_REQUIRE_DISTRIBUTION_SIGNING:-0}" == 1 ]]; then
  echo "Experimental Full USB may only be packaged in Vibe Controller Dev."; exit 1
fi
SERVICE_ID="$APP_ID.usb-service"
# Build the pinned source for our minimum OS instead of shipping a Homebrew
# bottle, which can require the builder's newer macOS version at runtime.
CACHE="$ROOT_DIR/.build/usb-dependency"
ARCHIVE="$CACHE/libusb-1.0.30.tar.bz2"
SOURCE="$CACHE/libusb-1.0.30"
PREFIX="$CACHE/install-arm64-macos14"
mkdir -p "$CACHE"
if [[ ! -f "$ARCHIVE" ]]; then
  curl --fail --location --retry 2 \
    https://github.com/libusb/libusb/releases/download/v1.0.30/libusb-1.0.30.tar.bz2 \
    -o "$ARCHIVE.download"
  mv "$ARCHIVE.download" "$ARCHIVE"
fi
if [[ "$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')" != fea36f34f9156400209595e300840767ab1a385ede1dc7ee893015aea9c6dbaf ]]; then
  echo "libusb source checksum mismatch. Remove $ARCHIVE and retry."; exit 1
fi
if [[ ! -f "$PREFIX/lib/libusb-1.0.0.dylib" ]]; then
  tar -xjf "$ARCHIVE" -C "$CACHE"
  (
    cd "$SOURCE"
    MACOSX_DEPLOYMENT_TARGET=14.0 CFLAGS='-O2 -arch arm64 -mmacosx-version-min=14.0' \
      LDFLAGS='-arch arm64 -mmacosx-version-min=14.0' \
      ./configure --prefix="$PREFIX" --disable-static --enable-shared
    make -j4
    make install
  )
fi
HELPERS="$APP/Contents/Helpers"
LICENSES="$APP/Contents/Resources/Licenses"
mkdir -p "$HELPERS" "$LICENSES"
install -m 755 "$PREFIX/lib/libusb-1.0.0.dylib" "$HELPERS/libusb-1.0.0.dylib"
install -m 644 "$SOURCE/COPYING" "$LICENSES/libusb-LGPL-2.1.txt"
# Include corresponding library source, not just an external download offer.
install -m 644 "$ARCHIVE" "$LICENSES/libusb-1.0.30-source.tar.bz2"
clang -std=c11 -fblocks -Wall -Wextra -Werror -O2 -arch arm64 -mmacosx-version-min=14.0 \
  -DVIBE_USB_APP_ID="\"$APP_ID\"" \
  -I"$PREFIX/include/libusb-1.0" "$ROOT_DIR/Scripts/xbox_usb_session.c" "$ROOT_DIR/Scripts/xbox_usb_service.c" \
  -L"$PREFIX/lib" -lusb-1.0 -framework Security -framework CoreFoundation -framework SystemConfiguration \
  -o "$HELPERS/VibeUSBService"
LIBRARY_ID="$(otool -D "$PREFIX/lib/libusb-1.0.0.dylib" | sed -n '2p')"
install_name_tool -change "$LIBRARY_ID" '@loader_path/libusb-1.0.0.dylib' "$HELPERS/VibeUSBService"
install_name_tool -id '@loader_path/libusb-1.0.0.dylib' "$HELPERS/libusb-1.0.0.dylib"
DAEMONS="$APP/Contents/Library/LaunchDaemons"
mkdir -p "$DAEMONS"
PLIST="$DAEMONS/$SERVICE_ID.plist"
plutil -create xml1 "$PLIST"
plutil -insert Label -string "$SERVICE_ID" "$PLIST"
plutil -insert BundleProgram -string Contents/Helpers/VibeUSBService "$PLIST"
plutil -insert MachServices -xml "<dict><key>$SERVICE_ID</key><true/></dict>" "$PLIST"
plutil -insert AssociatedBundleIdentifiers -xml "<array><string>$APP_ID</string></array>" "$PLIST"
plutil -insert ProcessType -string Interactive "$PLIST"
plutil -insert ExitTimeOut -integer 10 "$PLIST"
plutil -lint "$PLIST"
SIGN=(--force --sign "$IDENTITY")
if [[ "${VIBE_CONTROLLER_REQUIRE_DISTRIBUTION_SIGNING:-0}" == 1 ]]; then
  SIGN+=(--options runtime --timestamp)
fi
codesign "${SIGN[@]}" "$HELPERS/libusb-1.0.0.dylib"
codesign "${SIGN[@]}" --identifier "$SERVICE_ID" "$HELPERS/VibeUSBService"
codesign --verify --strict "$HELPERS/VibeUSBService"
