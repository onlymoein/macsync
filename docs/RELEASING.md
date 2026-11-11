# Releasing MacSync

Nothing in this repo publishes anything for you. `scripts/release.sh` only creates files in
`build/release/`. Pushing, tagging, uploading and updating the tap are manual steps below.

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

## Cutting a release

1. Set the version in `Sources/MacSyncCore/Environment.swift` (`appVersion`) and commit.
2. Run the script:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (ABCDE12345)" NOTARY_PROFILE=macsync-notary scripts/release.sh
```

It runs the tests, builds, signs (hardened runtime, secure timestamp), submits to Apple and waits,
staples the ticket, checks it with `spctl`, zips the app, and writes the checksum and a filled-in
`macsync.rb`. It stops at the first error, and refuses to run with the wrong kind of certificate.

3. Publish, by hand, once you're happy with `build/release/`:

```bash
git tag v0.2.0 && git push origin v0.2.0
```

```bash
gh release create v0.2.0 build/release/MacSync-0.2.0.zip --title "MacSync 0.2.0" --notes "Release notes here"
```

4. Update the tap. Copy `build/release/macsync.rb` to `Casks/macsync.rb` in
   `onlymoein/homebrew-tap`, replacing the old Python formula if it is still there, then commit
   and push.
5. On a Mac that has never had MacSync, check the whole path:

```bash
brew tap onlymoein/tap && brew trust onlymoein/tap && brew install --cask macsync
```

## Checks worth doing before the first public release

- Run it on two real Macs signed in to the same Apple Account. All testing so far was on one Mac.
- Test on macOS 13. Development was on a newer macOS.
- Open the notarized app from the zip on a clean Mac and confirm there is no Gatekeeper warning.
- The old tap formula installs the Python prototype. Remove or replace it so users don't get it.

## Pro pricing

`ProLicense.enforced` in `Sources/MacSyncCore/Pro.swift` is `false`, so Pro is on for everyone.
Turning it on needs a real `licenseIsValid()`. The landing page says Pro pricing is "to be
announced", so update `docs/index.html` when you decide.
