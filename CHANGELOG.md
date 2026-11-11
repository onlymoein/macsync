# Changelog

## 0.6.4
- ArtCraft has its own section, with the real Craft icons, now including CADCraft, FigCraft, SoundCraft and ArtCraft. ArtCraft Launcher does the installing, into its own install folder, so it knows about every app: MacSync installs the launcher if needed and opens it.
- An update that finds the sync window open installs as soon as you close it.

## 0.6.3
- The ArtCraft suite is always offered as one row, even when none of your Macs has it. Get All installs the missing Craft apps with Homebrew into the folder you choose.

## 0.6.2
- Get All on a group asks which folder to install into, and remembers it (for example Applications/ArtCraft).
- A downloaded app that Homebrew also publishes installs fully through Homebrew instead of opening its installer.
- Apps from one developer show as one row: the ArtCraft suite is a single "ArtCraft · 11 apps" row with one Get All and one switch, and opens to show each app.

## 0.6.1
- An app installed with Homebrew on one Mac and downloaded on another shows once, as the Homebrew one.
- A Homebrew package that is already on the Mac another way counts as installed; one Homebrew no longer has stops being offered.
- Updates arrive soon after you start using the Mac: MacSync checks when it wakes, unlocks or you log in, and at most every 30 minutes. Homebrew copies refresh Homebrew first.
- Support MacSync in the gear menu.

## 0.6.0
- Signed with a Developer ID and notarized by Apple: no more "Move to Trash" or "Open Anyway".
- Settings and App settings sit lower in the sync window, after the Dock and apps.
- Apply Dock changes when you open the lid is on by default. History is in the gear menu.
- macsync:// links open the sync window or History; Raycast gains Open Sync Window and Show History.

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
