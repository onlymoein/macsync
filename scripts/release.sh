#!/bin/bash
# Builds, signs, notarizes and packages MacSync, then writes the Homebrew cask.
#
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE=macsync-notary \
#   scripts/release.sh
#
# This script only produces files in build/release/. It never pushes, tags, uploads or
# publishes anything. Those steps are listed at the end for you to run yourself.
# See docs/RELEASING.md for the one-time setup.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your 'Developer ID Application: ...' certificate name}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a keychain profile made with 'xcrun notarytool store-credentials'}"
case "$SIGN_IDENTITY" in
  "Developer ID Application:"*) ;;
  *) echo "SIGN_IDENTITY must be a Developer ID Application certificate. Apple Development and Apple Distribution certificates cannot be notarized for outside distribution." >&2; exit 1 ;;
esac
security find-identity -v -p codesigning ${SIGN_KEYCHAIN:+"$SIGN_KEYCHAIN"} | grep -qF "$SIGN_IDENTITY" \
  || { echo "No signing identity matching '$SIGN_IDENTITY' in your keychain." >&2; exit 1; }
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || { echo "Notary profile '$NOTARY_PROFILE' not found or not working. Run: xcrun notarytool store-credentials $NOTARY_PROFILE" >&2; exit 1; }

VERSION=$(sed -n 's/.*appVersion = "\(.*\)"/\1/p' Sources/MacSyncCore/Environment.swift)
OUT=build/release
ZIP="MacSync-$VERSION.zip"
rm -rf "$OUT"; mkdir -p "$OUT"

echo "==> Tests"
swift test 2>&1 | tail -3

echo "==> Build and sign $VERSION"
# Optional: SIGN_KEYCHAIN, a signing-only keychain (unlocked with SIGN_KEYCHAIN_PASSWORD_FILE),
# so codesign doesn't ask for the login password.
if [ -n "${SIGN_KEYCHAIN:-}" ] && [ -n "${SIGN_KEYCHAIN_PASSWORD_FILE:-}" ]; then
  security unlock-keychain -p "$(cat "$SIGN_KEYCHAIN_PASSWORD_FILE")" "$SIGN_KEYCHAIN"
fi
SIGN_IDENTITY="$SIGN_IDENTITY" SIGN_KEYCHAIN="${SIGN_KEYCHAIN:-}" scripts/build-app.sh
codesign --verify --strict --deep --verbose=2 build/MacSync.app

echo "==> Notarize (this waits for Apple, usually a few minutes)"
ditto -c -k --keepParent build/MacSync.app "$OUT/notarize.zip"
xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
rm "$OUT/notarize.zip"

echo "==> Staple and verify"
xcrun stapler staple build/MacSync.app
xcrun stapler validate build/MacSync.app
spctl --assess --type execute --verbose=2 build/MacSync.app

echo "==> Package"
ditto -c -k --keepParent build/MacSync.app "$OUT/$ZIP"
SHA=$(shasum -a 256 "$OUT/$ZIP" | awk '{print $1}')
echo "$SHA  $ZIP" > "$OUT/$ZIP.sha256"

echo "==> Cask"
sed -e "s/@VERSION@/$VERSION/g" -e "s/@SHA256@/$SHA/g" packaging/macsync.rb.template > "$OUT/macsync.rb"

cat <<EOF

Done. Files in $OUT/:
  $ZIP            the notarized, stapled app
  $ZIP.sha256     checksum
  macsync.rb      the cask, with the version and checksum filled in

Next, by hand (nothing was published):
  1. git tag v$VERSION && git push origin v$VERSION
  2. gh release create v$VERSION $OUT/$ZIP --title "MacSync $VERSION" --notes-file <your notes>
  3. cp $OUT/macsync.rb <homebrew-tap>/Casks/macsync.rb, commit, push
  4. On a clean Mac: brew tap onlymoein/tap && brew trust onlymoein/tap && brew install --cask macsync
EOF
