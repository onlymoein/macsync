#!/bin/bash
# Renders the real app views with made-up data (a "Mac Studio" and a "MacBook Air" that only
# use built-in Apple apps) into docs/assets. Nothing here touches your Dock, settings or iCloud.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=docs/assets
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT" "$WORK/icloud/MacSync/machines" "$WORK/air"

python3 -I - "$WORK" <<'PY'
import json, plistlib, sys, datetime
work = sys.argv[1]
now = datetime.datetime.now(datetime.timezone.utc)
iso = lambda d: d.strftime('%Y-%m-%dT%H:%M:%SZ')
def app(bundle, label, path):
    return {"kind": "app", "label": label, "bundleID": bundle, "path": path}
studio = [
    app("com.apple.Safari", "Safari", "/System/Applications/Safari.app"),
    app("com.apple.mail", "Mail", "/System/Applications/Mail.app"),
    app("com.apple.MobileSMS", "Messages", "/System/Applications/Messages.app"),
    app("com.apple.Maps", "Maps", "/System/Applications/Maps.app"),
    app("com.apple.Photos", "Photos", "/System/Applications/Photos.app"),
    app("com.apple.iCal", "Calendar", "/System/Applications/Calendar.app"),
    app("com.apple.reminders", "Reminders", "/System/Applications/Reminders.app"),
    app("com.apple.Notes", "Notes", "/System/Applications/Notes.app"),
    app("com.apple.Music", "Music", "/System/Applications/Music.app"),
    app("com.apple.TV", "TV", "/System/Applications/TV.app"),
    app("com.apple.AppStore", "App Store", "/System/Applications/App Store.app"),
    app("com.apple.systempreferences", "System Settings", "/System/Applications/System Settings.app"),
    app("com.apple.Terminal", "Terminal", "/System/Applications/Utilities/Terminal.app"),
]
values = {
    "com.apple.finder|ShowPathbar": True, "com.apple.finder|ShowStatusBar": True,
    "com.apple.finder|FXPreferredViewStyle": "clmv", "NSGlobalDomain|AppleShowAllExtensions": True,
    "com.apple.dock|magnification": True, "com.apple.dock|largesize": 72, "com.apple.dock|autohide": True,
    "com.apple.dock|show-recents": False, "com.apple.AppleMultitouchTrackpad|Clicking": True,
    "NSGlobalDomain|com.apple.swipescrolldirection": False, "NSGlobalDomain|KeyRepeat": 2,
    "NSGlobalDomain|InitialKeyRepeat": 15, "com.apple.screencapture|type": "png",
    "com.apple.screencapture|disable-shadow": True,
}
snap = {
    "schemaVersion": 2, "machineID": "demo-studio", "machineName": "Mac Studio", "osVersion": "macOS 26",
    "appVersion": "0.5.4", "firstSeenAt": iso(now - datetime.timedelta(days=30)), "savedAt": iso(now),
    "dock": {"changedAt": iso(now + datetime.timedelta(minutes=1)), "apps": studio, "tileSize": 48, "orientation": "bottom",
             "others": [{"kind": "folder", "label": "Downloads", "path": "~/Downloads",
                         "folder": {"arrangement": 2, "displayAs": 0, "showAs": 1, "preferredItemSize": -1}}]},
    "inventory": {"brewAvailable": True, "casks": ["ghostty", "raycast", "rectangle"], "formulae": ["bat", "jq", "ripgrep"],
                  "appStore": [{"id": "424389933", "name": "Final Cut Pro"}, {"id": "1289583905", "name": "Pixelmator Pro"}]},
    "removals": [{"token": "cask:rectangle", "name": "Rectangle", "bundleID": "com.knollsoft.Rectangle",
                  "at": iso(now - datetime.timedelta(hours=2)), "active": True, "fromMachine": "Mac Studio"}],
    "settings": {"changedAt": iso(now + datetime.timedelta(minutes=1)), "covered": list(values), "values": values, "appDomains": []},
}
import hashlib, os
os.makedirs(work + "/icloud/MacSync/files", exist_ok=True)
os.makedirs(work + "/airhome", exist_ok=True)
def blob(text):
    data = text.encode()
    sha = hashlib.sha256(data).hexdigest()
    open(work + "/icloud/MacSync/files/" + sha, "wb").write(data)
    return {"sha": sha, "size": len(data), "changedAt": iso(now)}
files = {
    "~/.zshrc": blob("export EDITOR=nvim\nalias ll='ls -la'\nalias gs='git status'\neval \"$(starship init zsh)\"\n"),
    "~/.gitconfig": blob("[user]\n  name = Demo\n[pull]\n  rebase = true\n[init]\n  defaultBranch = main\n"),
    "~/.config/ghostty/config": blob("theme = catppuccin-mocha\nfont-size = 14\n"),
    "~/.claude/CLAUDE.md": blob("# How I like to work\n\n- Small, focused changes\n- Run the tests before saying it's done\n"),
    "~/.claude/skills/release-notes/SKILL.md": blob("---\nname: release-notes\n---\nWrite release notes from the git log.\n"),
    "~/.codex/AGENTS.md": blob("Prefer clear names over comments.\n"),
}
snap["extras"] = {"files": files, "loginItems": [], "packages": []}
json.dump(snap, open(work + "/icloud/MacSync/machines/demo-studio.json", "w"))
open(work + "/airhome/.gitconfig", "w").write("[user]\n  name = Demo\n[pull]\n  rebase = false\n")
os.utime(work + "/airhome/.gitconfig", (0, 86400 * 365 * 30))
def tile(b, label, path):
    return {"GUID": abs(hash(b)) % 100000, "tile-type": "file-tile", "tile-data": {
        "file-label": label, "bundle-identifier": b, "file-type": 41,
        "file-data": {"_CFURLString": "file://" + path.replace(" ", "%20") + "/", "_CFURLStringType": 15}}}
air = [studio[1], studio[7], studio[12], studio[5], studio[0]]
plistlib.dump({"tilesize": 48.0, "persistent-apps": [tile(a["bundleID"], a["label"], a["path"]) for a in air],
               "persistent-others": []}, open(work + "/air/dock.plist", "wb"))
PY
cat > "$WORK/brew" <<'BREW'
#!/bin/sh
case "$1" in list) echo rectangle ;; leaves) echo jq ;; *) exit 0 ;; esac
BREW
chmod +x "$WORK/brew"

run() { # extra env for this run; each run starts from a fresh copy of the demo Air
  rm -rf "$WORK/air/data"; cp "$WORK/air/dock.plist" "$WORK/air/dock.start"
  env MACSYNC_UI_PROBE="$OUT" MACSYNC_UI_PROBE_SECTIONS=1 MACSYNC_UI_PROBE_SELECT=all MACSYNC_UI_PROBE_HEIGHT="${HEIGHT:-1180}" \
    MACSYNC_SYNC_DIR="$WORK/icloud/MacSync" MACSYNC_DATA_DIR="$WORK/air/data" MACSYNC_DOCK_FILE="$WORK/air/dock.plist" \
    MACSYNC_HOME="$WORK/airhome" MACSYNC_MACHINE_ID=demo-air MACSYNC_MACHINE_NAME="MacBook Air" MACSYNC_BREW="$WORK/brew" "$@" \
    build/MacSync.app/Contents/MacOS/MacSync
}
UIPROBE=1 scripts/build-app.sh >/dev/null
for k in dock notInstalled artcraft apps appStore tools toRemove settings history files.config files.ai signIn homebrew; do
  defaults write com.onlymehdi.macsync "review.$k.open" -bool true
done
rm -f "$OUT"/section-*.png "$OUT"/review-*.png "$OUT"/menu-*.png "$OUT"/applied-*.png "$OUT"/menu-applied-*.png
run MACSYNC_UI_PROBE_DUMMY=1
cp "$WORK/air/dock.start" "$WORK/air/dock.plist"
run MACSYNC_UI_PROBE_DARK=1
for k in dock notInstalled artcraft apps appStore tools toRemove settings history files.config files.ai signIn homebrew; do
  defaults delete com.onlymehdi.macsync "review.$k.open" 2>/dev/null || true
done
scripts/build-app.sh >/dev/null   # leave a normal build behind, without the probe
ls -1 "$OUT"
