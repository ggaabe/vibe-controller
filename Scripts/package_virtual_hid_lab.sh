#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${ROOT_DIR}/dist/Virtual HID Lab.app"
EXECUTABLE="${ROOT_DIR}/.build/debug/VirtualHIDExperiment"
ENTITLEMENTS_FILE="${ROOT_DIR}/Experiments/VirtualHID/VirtualHIDExperiment.entitlements"
SIGNING_IDENTITY="${VIBE_CONTROLLER_SIGNING_IDENTITY:-Apple Development: Gabriel Garrett (Q527MSL34N)}"
PROFILE_PATH="${VIRTUAL_HID_PROVISIONING_PROFILE:-}"

if [[ ! -x "${EXECUTABLE}" ]]; then
  echo "Missing ${EXECUTABLE}"
  echo "Run: swift build --product VirtualHIDExperiment"
  exit 1
fi

if [[ ! -f "${ENTITLEMENTS_FILE}" ]]; then
  echo "Missing entitlements file: ${ENTITLEMENTS_FILE}"
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -Fq "\"${SIGNING_IDENTITY}\""; then
  echo "Configured signing identity not found: ${SIGNING_IDENTITY}"
  exit 1
fi

mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${EXECUTABLE}" "${APP_DIR}/Contents/MacOS/VirtualHIDExperiment"

cat > "${APP_DIR}/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>VirtualHIDExperiment</string>
  <key>CFBundleIdentifier</key>
  <string>com.vibe-controller.virtualhidlab</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Virtual HID Lab</string>
  <key>CFBundleDisplayName</key>
  <string>Virtual HID Lab</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF

if [[ -n "${PROFILE_PATH}" ]]; then
  if [[ ! -f "${PROFILE_PATH}" ]]; then
    echo "Provisioning profile not found: ${PROFILE_PATH}"
    exit 1
  fi
  cp "${PROFILE_PATH}" "${APP_DIR}/Contents/embedded.provisionprofile"
fi

codesign --force --deep --sign "${SIGNING_IDENTITY}" --entitlements "${ENTITLEMENTS_FILE}" "${APP_DIR}"
echo "Packaged ${APP_DIR}"
echo
echo "Embedded entitlements:"
codesign -d --entitlements :- "${APP_DIR}" 2>/dev/null || true
