#!/usr/bin/env bash
#
# Builds a universal, release-signed Fathom APK for a GitHub release upload,
# named for the pubspec version (no ABI marker, so the in-app updater treats it
# as the universal build). The versionCode is epoch seconds: always increasing,
# so the OS installer never rejects the update as a downgrade, with no counter
# to track by hand. The version NAME comes from pubspec.yaml, so bump that to the
# release version (e.g. 0.11.0-dev03) before running.
#
# Signed with the TraceApps family key (android/key.properties points at
# ~/.android/traceapps-release.keystore, as the other apps do).
#
# Usage:  scripts/build-apk.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

flutter build apk --release --build-number "$(date +%s)"

ver=$(grep -m1 '^version:' pubspec.yaml | sed 's/version:[[:space:]]*//; s/+.*//')
src="build/app/outputs/flutter-apk/app-release.apk"
out="build/app/outputs/flutter-apk/Fathom-${ver}.apk"
cp "$src" "$out"

traceapps=3a48b7ac46a209d5d1cc1bf66ae1e6a0188fefe802df0b21718b7ba5fbbde4c6
apksigner=$(ls -d "${ANDROID_HOME:-$HOME/Android/Sdk}"/build-tools/*/apksigner | sort -V | tail -1)

# Fathom signed with a key of its own before it moved to TraceApps: a phone
# with such a build updates over this one because the APK carries the old
# key's handover to the TraceApps key (APK Signature Scheme v3 rotation;
# Android 9 and later, while older Android still sees the old key, so that key
# is kept for good). The lineage and the old key's properties live beside the
# keystores, never in the repository.
lineage="$HOME/.android/fathom-to-traceapps.lineage"
old_props="${FATHOM_OLD_KEY_PROPERTIES:-$HOME/.android/fathom-key.properties.bak-2026-10-16}"
if [ -f "$lineage" ] && [ -f "$old_props" ]; then
  prop() { grep -o "^$2=.*" "$1" | cut -d= -f2-; }
  export OSP="$(prop "$old_props" storePassword)" OKP="$(prop "$old_props" keyPassword)"
  export NSP="$(prop android/key.properties storePassword)" NKP="$(prop android/key.properties keyPassword)"
  "$apksigner" sign \
    --ks "$(prop "$old_props" storeFile)" --ks-key-alias "$(prop "$old_props" keyAlias)" --ks-pass env:OSP --key-pass env:OKP \
    --next-signer --ks "$(prop android/key.properties storeFile)" --ks-key-alias "$(prop android/key.properties keyAlias)" --ks-pass env:NSP --key-pass env:NKP \
    --lineage "$lineage" --rotation-min-sdk-version 28 "$out"
  "$apksigner" lineage --in "$out" --print-certs | grep -q "$traceapps" ||
    { echo "The handover to the TraceApps key isn't in $out"; exit 1; }
  echo "Signed with the old Fathom key's handover to the TraceApps key"
else
  "$apksigner" verify --print-certs "$out" | grep -q "certificate SHA-256 digest: $traceapps" ||
    { echo "Not signed with the TraceApps key, and no handover from the old Fathom key ($lineage)"; exit 1; }
  echo "No key handover ($lineage missing): copies signed with the old Fathom key can't update over this one"
fi

echo ""
echo "Built universal release APK:"
echo "  $out"
echo "Upload this to the GitHub release for v${ver}."
