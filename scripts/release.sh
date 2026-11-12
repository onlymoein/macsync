#!/bin/bash
# Builds, signs and packages MacSync for the New channel: a zip, a disk image and checksums.
#
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/release.sh
#
# This script only produces files in build/release/. It never pushes, tags, uploads or
# publishes anything. The steps after it are listed at the end; see docs/RELEASING.md.
#
# Channels: a version goes out first as a GitHub pre-release, which only the New channel takes.
# scripts/notarize.sh then has Apple notarize it and makes the same release the latest one,
# which is Stable, and points Homebrew at it.
set -euo pipefail
cd "$(dirname "$0")/.."

# Optional: SIGN_KEYCHAIN, a signing-only keychain holding the Developer ID, unlocked with the
# password in SIGN_KEYCHAIN_PASSWORD_FILE, so nothing asks for the login password.
if [ -n "${SIGN_KEYCHAIN:-}" ] && [ -n "${SIGN_KEYCHAIN_PASSWORD_FILE:-}" ]; then
  security unlock-keychain -p "$(cat "$SIGN_KEYCHAIN_PASSWORD_FILE")" "$SIGN_KEYCHAIN"
fi

: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your 'Developer ID Application: ...' certificate name}"
case "$SIGN_IDENTITY" in
  "Developer ID Application:"*) ;;
  *) echo "SIGN_IDENTITY must be a Developer ID Application certificate. Unsigned and development builds never go out, on either channel." >&2; exit 1 ;;
esac
security find-identity -v -p codesigning ${SIGN_KEYCHAIN:+"$SIGN_KEYCHAIN"} | grep -qF "$SIGN_IDENTITY" \
  || { echo "No signing identity matching '$SIGN_IDENTITY' in your keychain." >&2; exit 1; }

VERSION=$(sed -n 's/.*appVersion = "\(.*\)"/\1/p' Sources/MacSyncCore/Environment.swift)
OUT=build/release
rm -rf "$OUT"; mkdir -p "$OUT"

echo "==> Tests"
swift test 2>&1 | tail -3

echo "==> Build and sign $VERSION"
SIGN_IDENTITY="$SIGN_IDENTITY" SIGN_KEYCHAIN="${SIGN_KEYCHAIN:-}" scripts/build-app.sh
codesign --verify --strict --deep --verbose=2 build/MacSync.app

echo "==> Package"
scripts/package.sh build/MacSync.app "$OUT" "$VERSION"

cat <<EOF

Done. Files in $OUT/: MacSync-$VERSION.zip, MacSync-$VERSION.dmg, MacSync.dmg, checksums.
Signed, not notarized yet: this is a New-channel build.

Next, by hand (nothing was published):
  1. git push, then publish it as a pre-release (New channel only):
     gh release create v$VERSION $OUT/MacSync-$VERSION.zip $OUT/MacSync-$VERSION.zip.sha256 \\
       $OUT/MacSync-$VERSION.dmg $OUT/MacSync.dmg --prerelease --title "MacSync $VERSION" --notes "..."
  2. scripts/notarize.sh $VERSION <homebrew-tap folder>
     Waits for Apple, swaps in the notarized files, makes the release Stable and updates the cask.
EOF
