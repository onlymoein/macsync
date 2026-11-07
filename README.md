# MacSync

Keep all your Macs set up the same way: Dock layout, installed apps and, later, settings.
Sync goes through your own iCloud Drive. There is no server.

Status: the free tier runs on one Mac. It has not been tested across two physical Macs yet,
and it isn't signed or notarized yet.

## What it does

- **Dock:** apps, folders, spacers, links, order, position and size. Apps match by bundle ID,
  so they still line up when their paths differ between Macs.
- **Apps:** Homebrew casks and formulae, and Mac App Store apps. You tick what you want.
  MacSync never uninstalls anything.
- **Safety:** a preview before every apply, a restore point before every apply, and one-click undo.

## How sync works

Each Mac writes only its own file, `iCloud Drive/MacSync/machines/<id>.json`, so iCloud never
has to merge anything. MacSync checks every 5 minutes and on wake, and it saves this Mac's setup
when it changes. It doesn't change a Mac until you review and apply.

**When two Macs change the Dock, the latest change wins.** The other Mac is offered that layout,
and a restore point is saved before it applies. A newly added Mac never beats an established one,
because its starting Dock doesn't count as an edit. If an app in the layout isn't on this Mac, it
is left out and listed. This relies on each Mac's clock.

Only an allowlist of fields is ever synced: names, bundle IDs, paths, Dock options and app lists.
Bookmarks stay on the Mac, your user folder is written as `~`, and logins and secret-looking
parameters are stripped from Dock links.

## Build and run

Requires Xcode. The app runs on macOS 13 or later.

```bash
swift test
```

```bash
scripts/build-app.sh
```

```bash
open build/MacSync.app
```

## CLI

The CLI is inside the app, at `MacSync.app/Contents/Helpers/macsync`.

```text
macsync status             Show each Mac and whether it's in sync
macsync sync               Save this Mac's setup and check the others (changes nothing here)
macsync preview            Show what applying would change
macsync apply              Apply, after showing the preview and asking
    --yes                  Don't ask (required when not run from a terminal)
    --no-dock              Leave the Dock alone
    --install a,b          Also install these (cask:ghostty,formula:jq,mas:497799835)
    --all-apps             Also install everything your other Macs have
macsync undo [--yes]       Undo the last apply
macsync restore-points     List saved restore points
```

## Raycast

`raycast/` has Sync Now, Apply Dock Layout, Undo Last Apply and Show Status. They call the same CLI.

```bash
cd raycast && npm install && npm run dev
```

## Good to know

- Mac App Store apps open on their App Store page for you to click Get. `mas install` needs root,
  so MacSync doesn't use it, and App Store IDs come from Spotlight, so it needs no extra tools.
- Casks that ask for an admin password fail and are reported, because MacSync never waits on a prompt.
- Undo restores the Dock. Installed apps stay installed, and MacSync tells you which ones.

## Layout

- `Sources/MacSyncCore`: everything that matters, shared by the app and CLI
- `Sources/MacSyncApp`: the menu bar app
- `Sources/macsync`: the CLI
- `Tests/MacSyncCoreTests`: unit tests, using a simulated Dock that behaves like the real one
