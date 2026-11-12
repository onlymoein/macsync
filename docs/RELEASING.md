# Releasing MacSync

`scripts/release.sh` only creates files in `build/release/`. Publishing the pre-release is a
manual step, and `scripts/notarize.sh` publishes (it replaces release files, marks the release
latest and pushes the cask), so run it only once the release is approved.

## One-time setup

### 1. A Developer ID Application certificate

Apple only lets Gatekeeper trust software distributed outside the App Store when it is signed with
a **Developer ID Application** certificate and notarized. "Apple Development" and "Apple
Distribution" certificates do not work for this.

1. Join the Apple Developer Program, if you haven't.
2. In Xcode, Settings, Accounts, Manage Certificates, add **Developer ID Application**.
   (Or create it at developer.apple.com, Certificates.)
3. Check it is installed:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

The name inside the quotes, like `Developer ID Application: Your Name (ABCDE12345)`, is your
`SIGN_IDENTITY`.

### 2. A notary profile

Create an app-specific password at account.apple.com, then store it in your keychain once:

```bash
xcrun notarytool store-credentials macsync-notary --apple-id you@example.com --team-id ABCDE12345
```

It prompts for the app-specific password. `macsync-notary` is your `NOTARY_PROFILE`.

## Channels: Stable and Beta

Beta was called New until 0.8.22. It's still stored as `new` in the settings, so nobody's choice changed.

Every build that goes out is signed with the Developer ID. Unsigned and development builds never
go out. A version passes through two channels:

| Channel | What it gets | Where it comes from |
| --- | --- | --- |
| **Beta** | Each version as soon as it's out, before Apple has finished notarizing it | GitHub pre-releases, read from the releases feed |
| **Stable** (the default) | Only versions Apple has notarized, which macOS opens without warnings | The latest GitHub release, which is never a pre-release |

People choose in the welcome window or in Settings, MacSync Versions. Homebrew and the website's
download button only ever get Stable. Switching from Beta back to Stable never goes down a
version: MacSync waits until Stable passes the copy it has.

A Beta build that's downloaded in a browser isn't notarized yet, so macOS warns about it. That's
why Beta is only offered inside the app, where updates download without that warning.

## Cutting a release

1. Set the version in `Sources/MacSyncCore/Environment.swift` (`appVersion`), add it to
   `CHANGELOG.md`, and commit.
2. Build the Beta-channel files:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (ABCDE12345)" scripts/release.sh
```

It runs the tests, builds and signs (hardened runtime, secure timestamp), then writes to
`build/release/`: the zip that updates use, a disk image whose window says to drag MacSync into
Applications, `MacSync.dmg` (the same image without the version, for the website's link) and
checksums. It refuses to run with anything but a Developer ID Application certificate.

3. Push, and publish it as a pre-release. Only the Beta channel takes it:

```bash
gh release create v0.2.0 build/release/MacSync-0.2.0.zip build/release/MacSync-0.2.0.zip.sha256 build/release/MacSync-0.2.0.dmg build/release/MacSync.dmg --prerelease --title "MacSync 0.2.0" --notes "Release notes here"
```

4. Make it Stable:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (ABCDE12345)" scripts/notarize.sh 0.2.0 ~/path/to/homebrew-tap
```

It submits the app to Apple and waits, staples the ticket, packs and notarizes the disk image,
replaces the release's files with the notarized ones, marks the release as the latest one (which
is what Stable reads), and commits the cask with the new version and checksum to the tap. It
stops at the first error, so a version Apple refuses stays on Beta.

5. On a Mac that has never had MacSync, check the whole path:

```bash
brew tap onlymoein/tap && brew trust onlymoein/tap && brew install --cask macsync
```

### The disk image

`scripts/make-dmg.sh <app> <dmg>` builds it with `hdiutil`. Finder lays out the window (icons, the
background from `scripts/make-dmg-background.swift`), so the first run may ask to let Terminal
control Finder.

## Checks worth doing before the first public release

- Run it on two real Macs signed in to the same Apple Account. All testing so far was on one Mac.
- Test on macOS 13. Development was on a newer macOS.
- Open the notarized app from the zip on a clean Mac and confirm there is no Gatekeeper warning.
- The old tap formula installs the Python prototype. Remove or replace it so users don't get it.

## Pro pricing

`ProLicense.enforced` in `Sources/MacSyncCore/Pro.swift` is `false`, so Pro is on for everyone.
Turning it on needs a real `licenseIsValid()`. The landing page says Pro pricing is "to be
announced", so update `docs/index.html` when you decide.

## The website

The site in `site/` builds into `docs/` with `cd site && npm run build`. It takes the version
from `Sources/MacSyncCore/Environment.swift`, so rebuild it after a version bump. If a release
goes out without a rebuild, the page still shows the newest version: it reads it from the
Homebrew cask when it opens.

## Fixes without a release: the rules file

`docs/rules.json` is published with the website (https://onlymoein.github.io/macsync/rules.json).
Every MacSync downloads it at most every six hours, after a sync, and uses it straight away. It's
data only, never code, so it can't change how MacSync works or looks; that still needs a release.

What it can do:

| Field | What it's for | Example |
| --- | --- | --- |
| `sameApps` | A Homebrew cask and the bundle IDs its app has when installed another way | `{"cask": "tailscale-app", "bundleIDs": ["io.tailscale.ipn.macsys"]}` |
| `caskRenames` | A cask Homebrew renamed: old name to new one | `{"old-name": "new-name"}` |
| `neverOffer` | Apps never offered from other Macs, by token | `["cask:some-app"]` |
| `notices` | A note in the menu, optionally for some versions only (at most 3, 200 characters each) | `{"id": "x", "text": "…", "below": "0.8.21"}` |
| `off` | Automatic actions to stop everywhere until a fix ships: `autoApplyDock`, `autoUpgrade` | `["autoUpgrade"]` |

To change it:

1. Edit `docs/rules.json` and raise `version` by one. MacSync refuses a file with a lower version
   than one it already has, so an old file can't be served again to undo a fix.
2. Sign it: `swift scripts/sign-rules.swift`. This writes `docs/rules.json.sig` with the private key
   in `~/.macsync-signing/rules-key`. That key never goes in the repository; MacSync has only its
   public half (`CloudRulesStore.publicKey`) and ignores any file it didn't sign.
3. Commit both files and push. GitHub Pages serves them within a minute or two.

If the private key is lost, make a new one, put its public half in `CloudRulesStore.publicKey`
and release: copies that have the old key keep their last good rules until they update.
