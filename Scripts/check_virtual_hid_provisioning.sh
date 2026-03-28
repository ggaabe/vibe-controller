#!/usr/bin/env bash
set -euo pipefail

PROFILE_DIR="${HOME}/Library/MobileDevice/Provisioning Profiles"
TARGET_ENTITLEMENT="com.apple.developer.hid.virtual.device"

echo "Signing identities:"
security find-identity -v -p codesigning || true
echo

if [[ ! -d "${PROFILE_DIR}" ]]; then
  echo "No provisioning profile directory found at ${PROFILE_DIR}"
  exit 0
fi

found_any=0
found_target=0

shopt -s nullglob
for profile in "${PROFILE_DIR}"/*.mobileprovision; do
  found_any=1
  plist="$(security cms -D -i "${profile}" 2>/dev/null || true)"
  if [[ -z "${plist}" ]]; then
    continue
  fi

  name="$(echo "${plist}" | plutil -extract Name raw -o - - 2>/dev/null || basename "${profile}")"
  team="$(echo "${plist}" | plutil -extract TeamIdentifier.0 raw -o - - 2>/dev/null || echo "?")"
  app_id="$(echo "${plist}" | plutil -extract Entitlements.application-identifier raw -o - - 2>/dev/null || echo "?")"
  has_entitlement="$(echo "${plist}" | plutil -extract "Entitlements.${TARGET_ENTITLEMENT}" raw -o - - 2>/dev/null || echo "false")"

  echo "Profile: ${name}"
  echo "  Team: ${team}"
  echo "  App ID: ${app_id}"
  echo "  ${TARGET_ENTITLEMENT}: ${has_entitlement}"
  echo "  File: ${profile}"
  echo

  if [[ "${has_entitlement}" == "1" || "${has_entitlement}" == "true" ]]; then
    found_target=1
  fi
done

if [[ "${found_any}" -eq 0 ]]; then
  echo "No provisioning profiles found in ${PROFILE_DIR}"
  exit 0
fi

if [[ "${found_target}" -eq 0 ]]; then
  echo "No installed provisioning profile grants ${TARGET_ENTITLEMENT}."
  echo "You will need Apple-approved access to that entitlement before the virtual HID lab can be provisioned successfully."
fi
