# Changelog

## 0.7.2
- After adding or removing a Craft app, ArtCraft Launcher comes back hidden in the menu bar, the way it was, instead of opening its window.
- Automatic updates leave Craft apps to ArtCraft Launcher, which keeps them up to date itself.

## 0.7.1
- **Apps and tools stay up to date:** on open and every six hours, MacSync updates every Homebrew app and command-line tool, including apps that update themselves like Raycast, plus npm global packages and uv tools. An app that's open waits, with a Quit and Update button, so nothing quits under you. Switch it off in the menu or the new Updates section.
- **Self-update no longer goes through Homebrew:** MacSync replaces itself directly, which macOS allows, instead of asking Homebrew to, which macOS can block halfway and leave no app behind ("It seems the App source '/Applications/MacSync.app' is not there").
- An app deleted after MacSync installed it is offered again instead of still showing Installed.
- Warnings use a darker amber that's easier to read on the menu's glass.

## 0.7.0
- **Config files:** shell (zsh, fish, bash, Starship), Git, editors (VS Code, Cursor, Zed, Neovim), terminals (Ghostty, kitty, Alacritty, WezTerm, tmux), Raycast's config folder and your fonts. The newest copy wins; a newer edit on this Mac is never replaced; each change shows its lines before you apply it. Files a dotfiles folder manages through links are left alone.
- **AI setup:** skills (`~/.agents`, Claude, Codex, Cursor), CLAUDE.md and AGENTS.md, agents, commands, rules, Claude Code settings, Claude Code and Claude app MCP servers, Codex config, Cursor rules and MCP servers. JSON files travel with secret-looking values taken out, and each Mac keeps its own keys when it's updated.
- **Secrets stay home:** any file with a key, token or password in it is kept on its Mac, and the window says which line. SSH and GPG keys, `~/.aws`, the 1Password and GitHub CLI config, shell history and `.env` files are never read. Every cleaned file is scanned again before it leaves the Mac.
- **More settings:** hot corners, input sources, keyboard shortcuts, app menu shortcuts, the fn key, and every trackpad gesture (built-in and Magic Trackpad).
- **Login items:** apps that open at login on your other Macs are added here when you apply.
- **Extensions and packages:** Homebrew taps, VS Code and Cursor extensions, npm global packages, uv tools, Claude Code plugins (with their marketplaces) and Steam games (downloaded by Steam).
- **App data:** Photoshop and Camera Raw presets; iStat Menus settings, without its license.
- **Better app matching:** apps installed from a .pkg (Office, Zoom) are matched to their Homebrew cask by bundle ID and uninstall paths, so other Macs install them with Homebrew.
- **Sign in to your apps:** after apps install, the ones that need an account are listed with a hint each, password manager first. MacSync opens each app; it never types a password.
- **Remove from this Mac or all Macs, everywhere:** every Remove now asks which, for apps, command-line tools, files, login items and packages.
- Undo and History put changed files back too.
- `macsync files` lists what this Mac shares and what it keeps back.

## 0.6.6
- Removing an ArtCraft app, one or all, asks: Remove from All Macs, or from This Mac Only. Other Macs mark apps removed elsewhere, with a Remove button, and stop offering them; installing one again brings it back everywhere.

## 0.6.5
- Remove and Remove All in the ArtCraft section: apps go to the Trash and come off ArtCraft Launcher's list.

## 0.6.4
- ArtCraft has its own section with every app in ArtCraft Launcher's catalog, official and community, as it grows: version, installed or not, update available, real icons. Install All and Update All.
- Craft apps come from their official downloads, checked against their published SHA-256 and their signing team, go into ArtCraft Launcher's install folder, and are recorded in the launcher's list so it knows them and keeps them updated.
- Checking for MacSync updates no longer uses GitHub's API, so GitHub's request limit never blocks it.
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
