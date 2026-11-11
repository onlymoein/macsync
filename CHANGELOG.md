# Changelog

## 0.8.2
- New MacSync releases show up sooner: opening the menu checks when it's been a couple of minutes, and MacSync looks every 10 minutes instead of every 30. `macsync://update` checks now.

## 0.8.1
- ArtCraft Launcher always installs first, and comes along when you install any Craft app on a Mac that doesn't have it.
- The ArtCraft section shows where apps go ("Installs into /Applications/Artcraft"), with Change…, and Install All asks first: Install, or Choose Another Folder…. A new Mac gets the launcher's own folder, /Applications/Artcraft, not Applications itself.
- A download without a published size shows how much has arrived (Downloading AniCraft… 84 MB) instead of sitting on Starting.
- The progress line shows how long the current item has taken once it's been a while (btop · 2 min), so slow doesn't look stuck.

## 0.8.0
- **Share My Setup:** the Share button in the sync window (or the settings menu) makes a .macsync file for a friend. Switch on the sections to give: apps, App Store apps, command-line tools and taps, extensions and plugins, settings, config files, AI setup, login items. Save it, or send it with AirDrop, Messages or Mail.
- Your friend double-clicks the file (or uses Open a Shared Setup…): everything in it shows up as "Your name's setup", with the usual preview and a switch on each item. Apps download from where they're published. A Shared with you section lists it, with Remove.
- **You can see it working:** installs, removals, ArtCraft and Homebrew updates show a progress bar with how many are done, what's happening now and what's next. Rows waiting their turn say Waiting; the one in progress says what it's doing. "Nothing to apply" no longer shows while something is running.
- The menu shows the same progress bar and what's next while MacSync works. The row being downloaded has its own bar.
- ArtCraft downloads show their percentage, then Installing. An icon that couldn't be fetched is tried again instead of staying blank.
- `macsync upgrade` updates everything from Terminal, and Raycast has Check Homebrew Updates, Update Homebrew Apps and Share My Setup. `macsync://share` opens the share sheet.
- ArtCraft apps whose icons haven't arrived yet show their first letter on blue instead of a grey square.
- Comparing shared files is worked out once per version instead of on every sync, so a big folder of skills doesn't keep the Mac busy or hold up installs.
- **Sign in to new apps** lists only apps MacSync installed that need an account (not every app on the Mac), with Sign In, a check mark and Clear; it hides when empty.
- Every section starts folded each time the window opens. Homebrew updates sits right after the Dock.
- Never in a shared setup: passwords, keys, tokens or any file with one, your fonts, app data, your Dock, your history, or apps' own preferences.

## 0.7.6
- The menu shows Homebrew at a glance: how many updates are waiting and which, with Update All, or what was just updated. Click it to open the window.
- The settings menu is grouped: Sync, Homebrew and MacSync, each with its own switches and Check for Updates Now.
- Each Mac's row shows its MacSync version only when it needs updating, and the version no longer repeats in the footer.

## 0.7.5
- **Homebrew updates** is its own section at the top of the window: what needs updating (from → to), Update and Update All, and an Install automatically switch. It opens by itself when something is waiting.
- The menu's items say what they do: Install Homebrew Updates Automatically, and Check Homebrew for Updates (which only lists them when automatic is off).

## 0.7.4
- **See what needs updating:** the Updates section lists every Homebrew app and tool, npm package and uv tool with a newer version, from → to, with Update on each row and Update All. With Automatic off, MacSync still checks on open and every six hours and lists them; with it on, it installs them.
- `macsync outdated` lists the same from Terminal.

## 0.7.3
- No more "Checking your Macs…" forever: files another Mac shares that are still in iCloud download in the background and show as still arriving, instead of being waited for one by one.
- Many files from one place (a folder of skills) fold into one row with Show, and a switch for all of them.
- A formula that's on this Mac as another one's dependency (poppler, ruby) is no longer offered as missing.
- The ArtCraft section shows ArtCraft's logo in its blue tile.
- The file, login item and package lists have one dropdown, not two: shared files sit under a heading, a row per group, with Show.
- Updates says Check Again when everything is up to date.
- A folder over 300 MB (presets, fonts) stops being copied past that size.
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
