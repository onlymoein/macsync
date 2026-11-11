# Changelog

## 0.6.0
- Signed with a Developer ID and notarized by Apple: no more "Move to Trash" or "Open Anyway".
- Settings and App settings sit lower in the sync window, after the Dock and apps.
- Apply Dock changes when you open the lid is on by default. History is in the gear menu.

## 0.5.7
- Each system setting has its own switch: keep one to this Mac, applied with Apply. The Settings section sits at the bottom when nothing needs applying.
- Uninstall any app or command-line tool from all your Macs right from the lists of apps on your other Macs.
- Clearer message when Homebrew no longer has a package.

## 0.5.6
- Apply Dock changes when you open the lid is now on by default.
- History is in the gear menu, and the History section shows even before your first Apply.

## 0.5.5
- Homebrew installs and upgrades work whether MacSync is open or not: a running MacSync restarts itself into the new version when its app is replaced.

## 0.5.4
- History: every Apply is saved, and you can go back to before any of the last 20, not only the last one (sync window, or `macsync restore <id>`).
- Updates and Homebrew now come from github.com/onlymoein/macsync: `brew tap onlymoein/tap && brew trust onlymoein/tap && brew install --cask macsync`.

## 0.5.3
- Optional: apply Dock changes from your other Macs when you open the lid.

## 0.5.0 – 0.5.2
- A full review of the sync window: switches are never lost to a running sync, errors stay on screen, Dock drag lands where you let go.
- App settings wait for Apply. The Settings section always shows what's in sync. The sync window follows your Dock live.

## 0.4.x
- Remove apps from all Macs (Homebrew uninstalls; others go to the Trash, App Store apps ask for your password). Choose what this Mac shares.
- Choose which Mac's Dock order every Mac keeps; rearrange and remove Dock icons in the sync window.
- App Store apps get their own section. Each Mac shows its MacSync version.
- The Dock is saved to iCloud a few seconds after you change it.

## 0.3.x
- Docks combined across Macs, with no main Mac. Removals reach every Mac.
- Apps you downloaded yourself come from the developer's own download, not iCloud.
- Switch off apps a Mac doesn't need. Collapsible sections with all on/off switches.
- MacSync updates itself.

## 0.2.0
- First test build: Dock, apps and settings through iCloud Drive, with preview, restore points and undo.
