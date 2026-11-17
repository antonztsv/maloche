# Development

## Build from source

You need macOS 26 or later and Xcode with the Swift 6 toolchain.

```bash
swift build
swift test
scripts/build-app.sh
```

`scripts/build-app.sh` signs the app, so it needs a local signing identity. `scripts/make-signing-cert.sh` creates a self-signed one in your login keychain (read the script first). The dev build lands in `build/maloche Dev.app` and uses its own bundle ID with a `.dev` suffix, so it never touches your real data.

## Screenshots

`scripts/screenshots.sh` renders every screen with sample data in light and dark into `build/screenshots/`, without showing a window. The README images land in `build/screenshots/readme/`; to update them, copy them into `docs/images/`:

```bash
scripts/screenshots.sh
cp build/screenshots/readme/*.png docs/images/
```

## Release

For a release build run `scripts/build-app.sh --release`. `scripts/release.sh` builds from a clean commit, signs and verifies the app, then puts the three release files into `build/upload/`: the signed disk image, the zip (the Sparkle update format) and `appcast.xml`, signed with the Sparkle key from your keychain. The disk image is built by [dmgbuild](https://github.com/dmgbuild/dmgbuild), which `scripts/release.sh` runs through `uvx` from [uv](https://docs.astral.sh/uv/); its layout lives in `scripts/dmg-settings.py`.

`scripts/release.sh` needs the signing identity whose SHA-256 is in `scripts/signing-fingerprint.txt` and uses the GitHub appcast as the update feed.

`scripts/test-update.sh` runs a local update test and uses the Sparkle private key from your keychain.

## Data

maloche keeps one SQLite database in the Application Support folder under its bundle ID: `~/Library/Application Support/io.github.antonztsv.maloche/`. Nothing leaves your Mac.

maloche backs up the database once a day (the last 30 are kept), by default into a `Backups` folder next to it; Settings > Backup lets you pick another folder, back up now or restore a backup. If you used Daily before, the same pane has "Import from Daily", which reads its JSON export of activities and timesheet.
