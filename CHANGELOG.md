# Changelog

## 0.8.17

- After Apply, the result says what went wrong when a file, package or login item didn't apply; before, it only said "Some changes didn't apply". It also lists the files, login items and packages that did.
- A Dock app that isn't installed here yet is a calm note, not a failure, and apps you switched off aren't mentioned.

## 0.8.16

- ArtCraft apps in their own folder (Applications/Artcraft) now count as on this Mac, so they aren't offered again from your other Macs. The ArtCraft chip at the top counts the way the ArtCraft section does.

## 0.8.15

- The chips at the top of the sync window are filters: click "12 apps to get" and only those sections show, opened, with Show Everything to go back. ArtCraft apps get their own chip, so the count matches what you see.
- Share shows how big the file is as you choose sections, and how your friend opens it. Files are compressed, about a third of the size; older files still open.
- An Import button, next to Share in the sync window and in the menu, opens a setup a friend shared.
- The menu's toolbar has Coffee in place of Undo (Undo is still in History).

## 0.8.14

- **Developer setup**: Xcode themes, key bindings, snippets and templates, and Android Studio keymaps, code styles, colors and templates sync like config files. Provisioning profiles, signing files and adb keys never leave the Mac.
- Xcode simulators and Android SDK packages (platforms, build tools, system images) are listed per Mac, with Install for the missing ones through Xcode and Google's sdkmanager. Android licenses are never accepted for you.
- Apps whose installer needs your Mac password now say so calmly, by name, and Install in Terminal works for developer apps Homebrew publishes too (Tailscale). Several at once get one "Install N in Terminal" button, and rows show Check while Terminal works.
- **A new menu layout**: Review Changes at the top, then Your Macs, then one Updates group for apps, tools and MacSync itself, and a toolbar with Sync, Undo, History, Share and Settings. Quit is in Settings. The menu no longer leaves an empty box above itself.
- MacSync's own update now installs while the sync window is open (it waits only while MacSync is busy). That window being open is what kept other Macs on an old version. A manual check's "up to date" note now goes away on its own.

## 0.8.13
- A command-line tool that's already on the Mac another way (vercel from npm, a binary you put there) is no longer offered again and again: its command in Homebrew's bin folder counts, and so does Homebrew saying it's already installed another way.
- In AI apps, the ones not on this Mac fold away under "Not on this Mac yet", closed until you open it.
- An update only counts when the new version is really on disk. A Mac whose Homebrew list is out of date said "already installed", MacSync took that as done, reopened on the old version, found the same update and went round in a loop. Now it stops and says what to do (brew update, then brew reinstall --cask macsync), and tries a failed version only once per run.

## 0.8.12
- **AI apps:** a section of its own with the well-known AI apps (ChatGPT, Claude, Gemini, Grok, Grok Bot, Muse from Meta, Microsoft 365 Copilot, GitHub Copilot, Perplexity, Comet, Codex, Cursor, Dia, Poe, Ollama, LM Studio and more), whether or not you have them. Install one or Install All, on all your Macs or this Mac only. See your version and Update or Update All. Homebrew apps install by themselves; App Store apps open their page.
- **MacSync no longer stalls when many things load at once.** Slow work (downloads, Homebrew, icons) used to run on Swift's shared threads; twenty icons loading together could take every one, and then syncs and installs couldn't start ("Starting…", "Preparing…"). It now runs on threads of its own.
- An ArtCraft install starts without looking ArtCraft's catalog up again, and a catalog that comes back incomplete (no icons or signing teams, when GitHub is limiting requests) no longer replaces the saved one. Only the next app says Preparing; the rest say Waiting.
- Config files, AI setup and Login items have an All on switch for what this Mac shares, and each login item can be kept to this Mac.
- An installer that needs your Mac password (Adobe Creative Cloud) says so, with Install in Terminal: Terminal opens with the install ready, and you type the password there.

## 0.8.11
- A Craft app's signature is read with Apple's codesign first (15 seconds), which doesn't check certificates over the network, and the Security framework second.
- Why an ArtCraft app didn't install stays on its row until it installs, whatever else refreshes the list.
- Every ArtCraft step is logged with its timing and result to ~/Library/Logs/MacSync/craft.log, and to MacSync/logs in your iCloud Drive so it can be read from your other Macs.
- A tool that moved from a Homebrew formula to a cask (vercel) counts as installed either way, so it's no longer offered again.

## 0.8.10
- **Apps that update themselves** (ChatGPT, Claude, Grok, Dropbox, TablePlus…) and weren't installed with Homebrew are now in the updates list when Homebrew publishes a newer version than the one on the Mac. Updating hands the app to Homebrew, which keeps it current from then on. App Store apps are listed too when `mas` is installed. The section is now App and Homebrew updates.
- Versions compare by their numbers only, so a nightly build (8.12.48-19.NIGHTLY) isn't mistaken for an older one.
- An ArtCraft install starts straight away even while MacSync is syncing; taking back a "removed on another Mac" mark now happens after the install. Rows say Preparing… until the first step.
- A sync can't hang: login items (which can wait on a macOS permission prompt), Homebrew taps, editor extensions, npm and uv are each read with a time limit.
- If MacSync is stopped while it has ArtCraft Launcher closed, it reopens the launcher, hidden, the next time it starts.

## 0.8.9
- Downloads can't sit silently: the row says "Connecting to ArtCraft's downloads" before the first byte, a connection that doesn't answer in 30 seconds or a download that stalls for a minute is retried twice and then stops with a plain reason (stopped making progress, couldn't be reached, too many requests), and the Install button tries again. App downloads from developers get the same limits.
- ArtCraft Launcher is made to quit if it declines, before MacSync writes its list, so it can't write its old list back over the new one.

## 0.8.8
- An ArtCraft Install pressed while a batch is running waits its turn ("After CADCraft") and runs right after, instead of starting a second batch alongside that overwrote the first one's progress and could leave the app showing Install with no error.
- A refresh of the ArtCraft list asked for while one is already running now runs again after it, so a finished install always shows as Installed.

## 0.8.7
- A Craft app's signature check waits at most 15 seconds. After 8 it says macOS is busy checking new apps. When the download matched ArtCraft's published checksum, the app installs right after, without asking macOS a second time; macOS checks the signature itself when the app first opens.

## 0.8.6
- ArtCraft installs copy the app off its disk image first, close the image, and check the copy on this Mac's own disk. Reading the freshly opened image is what held "Checking the signature" on some Macs while macOS scanned it. If macOS still doesn't answer, Apple's codesign gets a second try; if neither answers and the download matched ArtCraft's published checksum, the app installs and the row says why.
- macOS 26 and later open disk images with diskutil, which Apple now recommends over hdiutil.
- A tool that ignores being stopped can no longer freeze MacSync: it's stopped, then forced, then left behind.
- Each ArtCraft app goes into ArtCraft Launcher's list the moment it's installed, not at the end of the batch, with the launcher closed while the apps go in so it can't overwrite its list, and reopened hidden afterwards.
- Craft apps already in the install folder but missing from ArtCraft Launcher's list (installed by an earlier MacSync, like AniCraft) are added to it once, after a signature check, so the launcher stops offering to install them again.
- MacSync only quits and reopens ArtCraft Launcher for your real home folder, so its own tests no longer touch the launcher.

## 0.8.5
- A Homebrew install no longer holds up everything else while it runs. An ArtCraft install started during one (CADCraft after btop) sat on Waiting until Homebrew finished; now it starts straight away.
- Waiting says what it's after ("After btop"), and the progress line always names the item and count, even before its first step ("1 of 1 · CADCraft · starting").
- Each ArtCraft app shows its result the moment it's done, Installed or why it wasn't, instead of only after the whole batch. An app that failed no longer looks like it's still Waiting.
- Closing a Craft app's disk image gets 30 seconds, so a disk image something is still reading can't hold up the rest.
- Checking a Craft app's signature no longer runs Apple's codesign tool, which could sit on "Checking the signature" indefinitely. MacSync reads the signing team itself through macOS's Security framework, on the Mac with no network, and gives up after a minute with an error so you can try again.

## 0.8.4
- ArtCraft installs say which step they're on: Downloading, Verifying, Opening the disk image, Checking the signature, Copying into the folder.
- No step can wait forever: opening a disk image stops after 3 quiet minutes and copying after 10, with an error and the Install button to try again. A disk image with a license agreement is answered automatically.

## 0.8.3
- Homebrew installs say what they're doing on the row as it happens: Downloading btop… 12 MB (watched as it arrives), Installing, Installing what it needs, Building from source, or Waiting for another Homebrew job to finish.
- When Homebrew wants your Mac password, or Apple's Command Line Tools, the row says so and how to do it, instead of sitting on Installing.
- If Homebrew prints nothing for 10 minutes, MacSync stops it and says so, with Try Again.
- Automatic Homebrew updates wait while apps are installing, since Homebrew does one job at a time.

## 0.8.2
- The update check also reads GitHub's releases feed. GitHub's "latest release" address is cached and can point at the previous release for a while, which made a new release look missing ("0.8.0 is the latest version" when 0.8.1 was out).
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
