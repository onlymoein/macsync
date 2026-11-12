#!/bin/bash
# Packs an app into a disk image whose window shows MacSync, an arrow and Applications, so you
# drag one onto the other. Signs the image too when SIGN_IDENTITY is set.
#
#   scripts/make-dmg.sh <MacSync.app> <output.dmg>
#
# Finder lays out the window, so the first run may ask to let Terminal control Finder.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=$1; OUT=$2
NAME=MacSync
WORK=$(mktemp -d)
# Finder only lays out disks it can see, so it mounts in /Volumes like any disk image.
MOUNT="/Volumes/$NAME"
[ -e "$MOUNT" ] && { echo "Eject the disk named $NAME first." >&2; exit 1; }
trap 'hdiutil detach "$MOUNT" -quiet -force 2>/dev/null || true; rm -rf "$WORK"' EXIT

mkdir -p "$WORK/stage/.background"
ditto "$APP" "$WORK/stage/MacSync.app"
ln -s /Applications "$WORK/stage/Applications"
swift scripts/make-dmg-background.swift "$WORK/bg.png"
# 144 dpi, so Finder shows the 1320x800 picture at 660x400 and it stays sharp.
sips -s dpiWidth 144 -s dpiHeight 144 "$WORK/bg.png" --out "$WORK/stage/.background/background.png" >/dev/null

hdiutil create -quiet -srcfolder "$WORK/stage" -volname "$NAME" -fs HFS+ -format UDRW -size 200m "$WORK/rw.dmg"
hdiutil attach -quiet -readwrite -noverify -noautoopen "$WORK/rw.dmg"
osascript <<OSA
tell application "Finder"
  set d to disk "$NAME"
  open d
  set w to container window of d
  set current view of w to icon view
  set toolbar visible of w to false
  set statusbar visible of w to false
  set bounds of w to {200, 120, 860, 520}
  set o to icon view options of w
  set arrangement of o to not arranged
  set icon size of o to 128
  set text size of o to 13
  set background picture of o to file ".background:background.png" of d
  set position of item "MacSync.app" of d to {165, 200}
  set position of item "Applications" of d to {495, 200}
  update d without registering applications
  delay 1
  close w
end tell
OSA
rm -rf "$MOUNT/.fseventsd"
sync
hdiutil detach -quiet "$MOUNT"
rm -f "$OUT"
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT"
if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --identifier com.onlymehdi.macsync.dmg --sign "$SIGN_IDENTITY" ${SIGN_KEYCHAIN:+--keychain "$SIGN_KEYCHAIN"} --timestamp "$OUT"
fi
echo "$OUT"
