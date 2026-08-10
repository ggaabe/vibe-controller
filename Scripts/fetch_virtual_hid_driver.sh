#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DOWNLOAD_DIR="$ROOT_DIR/.build/downloads"
OUTPUT="$DOWNLOAD_DIR/Karabiner-DriverKit-VirtualHIDDevice-8.2.0.pkg"
EXPECTED_SHA256="7faf4c33046c2274726da9e29da795fb2d2ad81796557db0fcc1686c611eeafc"
URL="https://raw.githubusercontent.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/v8.2.0/dist/Karabiner-DriverKit-VirtualHIDDevice-8.2.0.pkg"

mkdir -p "$DOWNLOAD_DIR"

if [[ -f "$OUTPUT" ]]; then
  ACTUAL_SHA256="$(shasum -a 256 "$OUTPUT" | awk '{print $1}')"
  if [[ "$ACTUAL_SHA256" == "$EXPECTED_SHA256" ]] && \
     pkgutil --check-signature "$OUTPUT" | grep -Fq "Notarization: trusted by the Apple notary service"; then
    echo "Using cached, verified $OUTPUT"
    exit 0
  fi
fi

DOWNLOAD="$OUTPUT.download"
curl --fail --location --output "$DOWNLOAD" "$URL"

ACTUAL_SHA256="$(shasum -a 256 "$DOWNLOAD" | awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
  echo "Driver package checksum mismatch."
  exit 1
fi

pkgutil --check-signature "$DOWNLOAD" | grep -Fq "Notarization: trusted by the Apple notary service"
mv "$DOWNLOAD" "$OUTPUT"
echo "Downloaded and verified $OUTPUT"
