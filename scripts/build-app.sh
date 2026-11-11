#!/bin/bash
# Builds build/MacSync.app. Ad-hoc signed unless SIGN_IDENTITY names a certificate.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(sed -n 's/.*appVersion = "\(.*\)"/\1/p' Sources/MacSyncCore/Environment.swift)
FLAGS=()
if [ "${UIPROBE:-0}" = "1" ]; then FLAGS=(-Xswiftc -DUIPROBE); fi
# Universal by default (Apple silicon and Intel). ARCHS=arm64 builds faster for local use.
ARCH_FLAGS=()
for a in ${ARCHS:-arm64 x86_64}; do ARCH_FLAGS+=(--arch "$a"); done
swift build -c release "${ARCH_FLAGS[@]}" --product MacSyncApp ${FLAGS[@]+"${FLAGS[@]}"}
swift build -c release "${ARCH_FLAGS[@]}" --product macsync ${FLAGS[@]+"${FLAGS[@]}"}
BIN=$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)
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
  <key>NSAppleEventsUsageDescription</key><string>MacSync reads your login items, and adds the ones your other Macs open at login, through System Events.</string>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>com.onlymehdi.macsync</string>
    <key>CFBundleURLSchemes</key><array><string>macsync</string></array>
  </dict></array>
  <key>CFBundleDocumentTypes</key><array><dict>
    <key>CFBundleTypeName</key><string>MacSync Setup</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSHandlerRank</key><string>Owner</string>
    <key>LSItemContentTypes</key><array><string>com.onlymehdi.macsync.setup</string></array>
  </dict></array>
  <key>UTExportedTypeDeclarations</key><array><dict>
    <key>UTTypeIdentifier</key><string>com.onlymehdi.macsync.setup</string>
    <key>UTTypeDescription</key><string>MacSync Setup</string>
    <key>UTTypeConformsTo</key><array><string>public.json</string><string>public.data</string></array>
    <key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>macsync</string></array></dict>
  </dict></array>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict></plist>
PLIST

IDENTITY="${SIGN_IDENTITY:--}"
# Notarization requires a secure timestamp, which only a real identity can request.
TS="--timestamp=none"
if [ "$IDENTITY" != "-" ]; then TS="--timestamp"; fi
# SIGN_KEYCHAIN: a keychain used only for signing, so codesign never asks for the login password.
KC=()
if [ -n "${SIGN_KEYCHAIN:-}" ]; then KC=(--keychain "$SIGN_KEYCHAIN"); fi
codesign --force --options runtime $TS ${KC[@]+"${KC[@]}"} --sign "$IDENTITY" "$APP/Contents/Helpers/macsync"
codesign --force --options runtime $TS ${KC[@]+"${KC[@]}"} --entitlements packaging/MacSync.entitlements --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
# Keep macOS from opening this build copy (for macsync:// links or after an update) instead of
# the installed one in Applications.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP" 2>/dev/null || true
echo "Built $APP ($VERSION), signed with: $IDENTITY"
