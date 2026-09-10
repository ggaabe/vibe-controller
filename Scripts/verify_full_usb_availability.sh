#!/usr/bin/env bash
set -euo pipefail
APP="${1:?Usage: verify_full_usb_availability.sh packaged.app}"
APP_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
if [[ "$APP_ID" == com.vibe-controller.app.dev ]]; then
  if ! codesign -dv "$APP/Contents/Helpers/VibeUSBService" 2>&1 \
    | grep -Fx "Identifier=$APP_ID.usb-service" >/dev/null; then
    echo "Packaged USB helper lost its authentication identity."; exit 1
  fi
  PLIST="$APP/Contents/Library/LaunchDaemons/$APP_ID.usb-service.plist"
  [[ "$(plutil -extract BundleProgram raw "$PLIST")" == Contents/Helpers/VibeUSBService ]]
  [[ "$(plutil -extract Label raw "$PLIST")" == "$APP_ID.usb-service" ]]
  echo "Dev-only Full USB helper identity verified."
elif [[ "$APP_ID" == com.vibe-controller.app ]]; then
  for path in Contents/Helpers/VibeUSBService Contents/Helpers/VibeXboxUSBSession \
    Contents/Helpers/libusb-1.0.0.dylib Contents/Library/LaunchDaemons \
    Contents/Resources/Licenses/libusb-LGPL-2.1.txt \
    Contents/Resources/Licenses/libusb-1.0.30-source.tar.bz2; do
    if [[ -e "$APP/$path" ]]; then
      echo "Public app contains an experimental Full USB component: $path"; exit 1
    fi
  done
  [[ -f "$APP/Contents/Resources/VibeController-VirtualHardwareSupport.pkg" ]]
  echo "Public app excludes Full USB; Universal Control support is retained."
else
  echo "Unsupported packaged identity: $APP_ID"; exit 1
fi
