#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PREFIX="$ROOT/.build/usb-dependency/install-arm64-macos14"
if [[ ! -f "$PREFIX/lib/libusb-1.0.0.dylib" ]]; then
  echo 'Package the app first to build the pinned libusb dependency.'; exit 1
fi
OUT="$(mktemp -d /tmp/vibe-usb-tests.XXXXXX)"
trap 'rm -rf "$OUT"' EXIT
clang -std=c11 -Wall -Wextra -Werror -I"$PREFIX/include/libusb-1.0" \
  "$ROOT/Scripts/test_xbox_usb_session.c" -L"$PREFIX/lib" -lusb-1.0 -o "$OUT/session-tests"
"$OUT/session-tests"
