#!/bin/bash
# Builds build/MacSync.app. Ad-hoc signed unless SIGN_IDENTITY names a certificate.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(sed -n 's/.*appVersion = "\(.*\)"/\1/p' Sources/MacSyncCore/Environment.swift)
FLAGS=()
if [ "${UIPROBE:-0}" = "1" ]; then FLAGS=(-Xswiftc -DUIPROBE); fi
swift build -c release --product MacSyncApp ${FLAGS[@]+"${FLAGS[@]}"}
swift build -c release --product macsync ${FLAGS[@]+"${FLAGS[@]}"}
BIN=$(swift build -c release --show-bin-path)
APP=build/MacSync.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/MacSyncApp" "$APP/Contents/MacOS/MacSync"
cp "$BIN/macsync" "$APP/Contents/Helpers/macsync"

ICONSET=build/AppIcon.iconset
mkdir -p "$ICONSET"
swiftc -O scripts/make-icon.swift -o build/make-icon
for s in 16 32 128 256 512; do
  build/make-icon "$ICONSET/icon_${s}x${s}.png" "$s"
  build/make-icon "$ICONSET/icon_${s}x${s}@2x.png" "$((s * 2))"
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET" build/make-icon

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>MacSync</string>
  <key>CFBundleDisplayName</key><string>MacSync</string>
  <key>CFBundleExecutable</key><string>MacSync</string>
  <key>CFBundleIdentifier</key><string>com.onlymehdi.macsync</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict></plist>
PLIST

IDENTITY="${SIGN_IDENTITY:--}"
# Notarization requires a secure timestamp, which only a real identity can request.
TS="--timestamp=none"
if [ "$IDENTITY" != "-" ]; then TS="--timestamp"; fi
codesign --force --options runtime $TS --sign "$IDENTITY" "$APP/Contents/Helpers/macsync"
codesign --force --options runtime $TS --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($VERSION), signed with: $IDENTITY"
