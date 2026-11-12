#!/bin/bash
# Moves a release from New to Stable: has Apple notarize the app and the disk image, staples the
# tickets, replaces the release's files, marks the release as the latest one and points the
# Homebrew cask at it. Stable copies of MacSync only ever update to releases that went through this.
#
#   scripts/notarize.sh <version> <homebrew-tap folder>
#
# It uses build/MacSync.app, which must be the signed build of that version. It publishes, so run
# it only once the release is approved. NOTARY_PROFILE defaults to macsync-notary; SIGN_KEYCHAIN and
# SIGN_KEYCHAIN_PASSWORD_FILE as in release.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
V=$1; TAP=$2
PROFILE=${NOTARY_PROFILE:-macsync-notary}
KC=${SIGN_KEYCHAIN:-}
[ -n "$KC" ] && [ -n "${SIGN_KEYCHAIN_PASSWORD_FILE:-}" ] && security unlock-keychain -p "$(cat "$SIGN_KEYCHAIN_PASSWORD_FILE")" "$KC"
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY, to sign the disk image}"

BUILT=$(defaults read "$PWD/build/MacSync.app/Contents/Info" CFBundleShortVersionString)
[ "$BUILT" = "$V" ] || { echo "build/MacSync.app is $BUILT, not $V." >&2; exit 1; }
W=build/notary-$V; rm -rf "$W"; mkdir -p "$W"
ditto build/MacSync.app "$W/MacSync.app"

submit() {  # file
  xcrun notarytool submit "$1" --keychain-profile "$PROFILE" ${KC:+--keychain "$KC"} --wait --timeout 12h | tee -a "$W/notary.log"
  tail -20 "$W/notary.log" | grep -q "status: Accepted" || { echo "Apple didn't accept $1." >&2; exit 1; }
}

echo "==> Notarize the app"
ditto -c -k --keepParent "$W/MacSync.app" "$W/submit.zip"
submit "$W/submit.zip"; rm "$W/submit.zip"
xcrun stapler staple "$W/MacSync.app"
spctl -a -vv "$W/MacSync.app" 2>&1 | tee -a "$W/notary.log"

echo "==> Package and notarize the disk image"
SIGN_IDENTITY="$SIGN_IDENTITY" SIGN_KEYCHAIN="$KC" scripts/package.sh "$W/MacSync.app" "$W/out" "$V"
submit "$W/out/MacSync-$V.dmg"
xcrun stapler staple "$W/out/MacSync-$V.dmg"
cp "$W/out/MacSync-$V.dmg" "$W/out/MacSync.dmg"
(cd "$W/out" && shasum -a 256 "MacSync-$V.dmg" > "MacSync-$V.dmg.sha256")

echo "==> Replace the release's files and make it Stable"
gh release upload "v$V" --repo onlymoein/macsync --clobber "$W/out/MacSync-$V.zip" "$W/out/MacSync-$V.zip.sha256" \
  "$W/out/MacSync-$V.dmg" "$W/out/MacSync-$V.dmg.sha256" "$W/out/MacSync.dmg"
gh release edit "v$V" --repo onlymoein/macsync --prerelease=false --latest

echo "==> Point Homebrew at it"
SHA=$(awk '{print $1}' "$W/out/MacSync-$V.zip.sha256")
(cd "$TAP" && git pull -q --rebase)
sed -e "s/@VERSION@/$V/g" -e "s/@SHA256@/$SHA/g" packaging/macsync.rb.template > "$TAP/Casks/macsync.rb"
(cd "$TAP" && git add Casks/macsync.rb && git commit -qm "macsync $V (stable, notarized)" && git push -q)
echo "Done: $V is Stable and notarized, $SHA"
