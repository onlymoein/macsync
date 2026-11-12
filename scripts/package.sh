#!/bin/bash
# Zips an app and packs it into a disk image, with checksums, under the release's file names.
#   scripts/package.sh <MacSync.app> <output folder> <version>
# MacSync.dmg, without the version, is what the website's download link points at.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=$1; OUT=$2; V=$3
mkdir -p "$OUT"
rm -f "$OUT/MacSync-$V.zip"
ditto -c -k --keepParent "$APP" "$OUT/MacSync-$V.zip"
(cd "$OUT" && shasum -a 256 "MacSync-$V.zip" > "MacSync-$V.zip.sha256")
scripts/make-dmg.sh "$APP" "$OUT/MacSync-$V.dmg" >/dev/null
cp "$OUT/MacSync-$V.dmg" "$OUT/MacSync.dmg"
(cd "$OUT" && shasum -a 256 "MacSync-$V.dmg" > "MacSync-$V.dmg.sha256")
