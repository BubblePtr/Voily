# Releasing Voily Outside the Mac App Store

Voily is distributed as a signed macOS app through GitHub Releases rather than the Mac App Store. This document describes the local, manual release flow for producing a public artifact that users can download safely.

## Goals

- Ship `Voily.app` outside the Mac App Store
- Keep App Sandbox disabled
- Sign public builds with `Developer ID Application`
- Notarize the release artifact before uploading it to GitHub Releases

## Prerequisites

Before running the release flow, make sure the current Mac has:

- Xcode command line tools
- `dmgbuild` for deterministic drag-install DMG layout generation
- An Apple Developer membership
- A `Developer ID Application` certificate installed in the local keychain
- A configured `notarytool` keychain profile
- A Sparkle EdDSA key pair for in-app updates, generated on the release machine
- A Sparkle private key stored as a generic password in the self-hosted release runner's release keychain
- Xcode Metal Toolchain installed through `xcodebuild -downloadComponent MetalToolchain`

Install `dmgbuild` once on the release machine:

```bash
pipx install "dmgbuild==1.6.7"
```

If `pipx` is not available on the release machine, install `dmgbuild` into the release user's Python environment and make sure `dmgbuild --help` works in the GitHub Actions runner shell.

Check the available signing identities:

```bash
security find-identity -p codesigning -v
```

You should see a `Developer ID Application: ...` identity before you build a public release.

Create a reusable `notarytool` profile once per machine:

```bash
xcrun notarytool store-credentials "voily-notary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD"
```

Then export it for the release commands:

```bash
export VOILY_NOTARY_PROFILE=voily-notary
```

For the self-hosted release runner, store the `Developer ID Application` identity and the `voily-notary` profile in the dedicated release keychain:

```bash
/Users/openclaw/Library/Keychains/voily-release.keychain-db
```

The release workflow unlocks that keychain with the GitHub secret:

```text
VOILY_RELEASE_KEYCHAIN_PASSWORD
```

Sparkle uses a separate EdDSA key pair from Apple notarization. Generate it on the release machine:

```bash
unzip -q Vendor/Sparkle/Sparkle-for-Swift-Package-Manager.zip -d /tmp/voily-sparkle
/tmp/voily-sparkle/bin/generate_keys
```

Add the printed public key to release builds through the `VOILY_SPARKLE_PUBLIC_ED_KEY` build setting. Store the private key in the dedicated release keychain as a generic password so the headless self-hosted runner can read it after unlocking the keychain:

```bash
VOILY_RELEASE_KEYCHAIN="$HOME/Library/Keychains/voily-release.keychain-db"
VOILY_SPARKLE_KEYCHAIN_ACCOUNT="ed25519"
VOILY_SPARKLE_KEYCHAIN_SERVICE="dev.voily.sparkle.ed25519-private-key"

SPARKLE_PRIVATE_KEY="$(
  security find-generic-password \
    -a "$VOILY_SPARKLE_KEYCHAIN_ACCOUNT" \
    -s "Private key for signing Sparkle updates" \
    -w "$HOME/Library/Keychains/login.keychain-db"
)"

security add-generic-password -U \
  -a "$VOILY_SPARKLE_KEYCHAIN_ACCOUNT" \
  -s "$VOILY_SPARKLE_KEYCHAIN_SERVICE" \
  -l "Voily Sparkle EdDSA private key" \
  -T /usr/bin/security \
  -w "$SPARKLE_PRIVATE_KEY" \
  "$VOILY_RELEASE_KEYCHAIN"

unset SPARKLE_PRIVATE_KEY

security set-generic-password-partition-list \
  -a "$VOILY_SPARKLE_KEYCHAIN_ACCOUNT" \
  -s "$VOILY_SPARKLE_KEYCHAIN_SERVICE" \
  -S apple-tool:,apple: \
  "$VOILY_RELEASE_KEYCHAIN"
```

The release workflow reads that generic password from:

```text
account: ed25519
service: dev.voily.sparkle.ed25519-private-key
keychain: $HOME/Library/Keychains/voily-release.keychain-db
```

Do not commit the private key, API tokens, or keychain exports to the repository. Do not store the Sparkle private key in GitHub Secrets unless the release model is intentionally changed to GitHub-hosted CI.

## Versioning

Voily release versions use semantic versioning in the `MAJOR.MINOR.PATCH` form.

- `MARKETING_VERSION` in `project.yml` is the app version and must be a three-part semantic version, for example `0.1.0`.
- Public release tags use the same version with a leading `v`, for example `v0.1.0`.
- `CURRENT_PROJECT_VERSION` remains the build number and should stay an integer that can be incremented independently.
- The automated release workflow rejects tags that do not match `vMAJOR.MINOR.PATCH`.
- The automated release workflow also rejects tags that do not match `CFBundleShortVersionString`.
- Each public release must include `docs/releases/vMAJOR.MINOR.PATCH.md`. The workflow uses that file for both the GitHub Release body and the Sparkle update notes embedded into `appcast.xml`.

The current release version is `0.1.5`, so the matching tag is:

```bash
git tag v0.1.5
git push origin v0.1.5
```

Pre-release identifiers such as `v0.1.0-rc.1` are not accepted by the public release workflow yet, because the macOS app version stored in `CFBundleShortVersionString` is kept to the stable `MAJOR.MINOR.PATCH` form.

## Release commands

### 1. Archive the Release build

```bash
make release
```

This command:

- archives the `Release` configuration
- exports `Voily.app` to `build/release/Voily.app`

For local feature validation on a development machine, install the exported app directly:

```bash
make install-dev
```

This uses the same Release/Developer ID app bundle shape as the public release path, but does not create, notarize, or staple a `.dmg`.

If Xcode does not automatically pick the correct signing identity, pass it explicitly:

```bash
VOILY_CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" make release
```

### 2. Package the app

Recommended for public distribution:

```bash
make package-dmg
```

Optional zip artifact:

```bash
make package-zip
```

Artifacts are written to `build/release/artifacts/`.

`make package-dmg` creates the standard drag-to-install disk image with `dmgbuild`: `Voily.app` appears on the left, an `Applications` shortcut appears on the right, and `Resources/Release/dmg-background.png` is used as the Finder background image. `Resources/Release/dmg-background-source.png` keeps the original high-resolution image, while `dmg-background.png` is the Finder-ready derivative sized for the installer window. The layout is written directly into `.DS_Store`, so release packaging no longer depends on Finder or AppleScript access in the runner GUI session. To temporarily replace the background image, set `VOILY_DMG_BACKGROUND_PATH`.

`make package-dmg` will try to sign the disk image with the same identity used by the archived app. If you need to override that identity, set `VOILY_DMG_SIGN_IDENTITY`.

## 3. Verify the release bundle locally

```bash
make verify-release
```

This checks:

- bundle identifier
- codesign integrity
- Hardened Runtime
- current Gatekeeper assessment

If Gatekeeper rejects the app at this stage, that usually means the build is still using a development identity or has not been notarized yet.

## 4. Notarize the artifact

The recommended artifact to notarize is the dmg:

```bash
ARTIFACT=build/release/artifacts/Voily-0.1.5.dmg make notarize
ARTIFACT=build/release/artifacts/Voily-0.1.5.dmg make staple
ARTIFACT=build/release/artifacts/Voily-0.1.5.dmg make verify-release
```

Notes:

- `make notarize` requires `VOILY_NOTARY_PROFILE`
- `make staple` works for `.app` and `.dmg`, not `.zip`
- if you want a stapled zip, staple the `.app` first and recreate the zip afterward

## 5. Publish to GitHub Releases

The preferred publishing path is the GitHub Actions release workflow. It runs on the self-hosted release runner with these labels:

- `self-hosted`
- `macOS`
- `ARM64`
- `voily-release`

After the workflow is present on `main`, publish a release by creating and pushing the matching semantic version tag:

```bash
git tag v0.1.5
git push origin v0.1.5
```

The workflow will:

1. Check out the tagged commit.
2. Verify the runner, signing identity, and `VOILY_NOTARY_PROFILE`.
3. Run `make release`.
4. Confirm the tag matches `CFBundleShortVersionString`.
5. Run `make package-dmg`.
6. Run `make notarize`, `make staple`, and `make verify-release`.
7. Copy `docs/releases/${RELEASE_TAG}.md` next to the dmg with the same basename so Sparkle can use it as release notes.
8. Generate `appcast.xml` and any Sparkle delta files from the notarized release artifacts, with release notes embedded for the newest appcast item.
9. Create the GitHub Release if it does not exist, or update its title and notes before uploading the dmg, `appcast.xml`, and delta files with `--clobber`.

Manual publishing is still possible if the workflow is unavailable:

1. Create a git tag for the release version.
2. Push the tag to GitHub.
3. Open a new GitHub Release.
4. Upload the notarized `.dmg`, `appcast.xml`, and any generated `.delta` files.
5. Add release notes, minimum macOS version, and first-launch permission guidance.

## In-app updates with Sparkle

Voily includes Sparkle 2.9.2 for manual in-app update checks. The first implementation intentionally keeps automatic checks disabled and only starts Sparkle when `SUPublicEDKey` is populated with a real EdDSA public key.

The app currently points Sparkle at:

```text
https://github.com/BubblePtr/Voily/releases/latest/download/appcast.xml
```

Until the release machine has a Sparkle private key and publishes `appcast.xml`, the "Check for Updates..." menu item shows a local not-configured message instead of starting Sparkle.

When enabling appcast publishing on the release machine, generate the appcast from the folder that contains the notarized release artifacts:

```bash
unzip -q Vendor/Sparkle/Sparkle-for-Swift-Package-Manager.zip -d /tmp/voily-sparkle
RELEASE_TAG="v0.1.5"
security find-generic-password \
  -a ed25519 \
  -s dev.voily.sparkle.ed25519-private-key \
  -w "$HOME/Library/Keychains/voily-release.keychain-db" |
/tmp/voily-sparkle/bin/generate_appcast \
  --download-url-prefix "https://github.com/BubblePtr/Voily/releases/download/${RELEASE_TAG}/" \
  --ed-key-file - \
  build/release/artifacts
```

The generated appcast and any generated delta files must be uploaded with the release artifacts. Keep `CFBundleVersion` (`CURRENT_PROJECT_VERSION`) increasing for every public release, because Sparkle uses it as the machine-readable update version. Keep `CFBundleShortVersionString` (`MARKETING_VERSION`) as the user-facing semantic version that matches the release tag.

The automated workflow reads `docs/releases/${RELEASE_TAG}.md`, copies it next to the dmg with the same basename, and passes `--embed-release-notes` to `generate_appcast`. Manual releases should do the same so the Sparkle update window and the GitHub Release page show the same user-facing changes.

## Recommended release notes checklist

Include these user-facing details in each release:

- Version number
- Minimum system version: macOS 14.0+
- User-visible fixes and release-process fixes that affect downloads, installation, or updates
- First-launch permissions:
  - Microphone
  - Accessibility
- Whether local models or cloud API keys need extra setup

## Troubleshooting

### `make verify-release` says Hardened Runtime is missing

Make sure the `Release` build settings still have `ENABLE_HARDENED_RUNTIME = YES`.

### Gatekeeper says `rejected` before notarization

That is expected if the app is signed with `Apple Development` instead of `Developer ID Application`, or if the artifact has not been notarized yet.

### `make notarize` fails immediately

Check:

- `VOILY_NOTARY_PROFILE` is set
- `xcrun notarytool history --keychain-profile "$VOILY_NOTARY_PROFILE"` works
- the artifact path exists

### The app launches locally but users still see trust warnings

That usually means one of these steps is missing:

- signed with `Developer ID Application`
- notarized
- stapled
- repackaged after stapling when distributing a zip
