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
- An Apple Developer membership
- A `Developer ID Application` certificate installed in the local keychain
- A configured `notarytool` keychain profile
- A Sparkle EdDSA key pair for in-app updates, generated on the release machine

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

Sparkle uses a separate EdDSA key pair from Apple notarization. Generate it on the release machine and keep the private key in that Mac's Keychain:

```bash
unzip -q Vendor/Sparkle/Sparkle-for-Swift-Package-Manager.zip -d /tmp/voily-sparkle
/tmp/voily-sparkle/bin/generate_keys
```

Add the printed public key to release builds through the `VOILY_SPARKLE_PUBLIC_ED_KEY` build setting. Do not commit the private key, API tokens, or keychain exports to the repository.

## Versioning

Voily release versions use semantic versioning in the `MAJOR.MINOR.PATCH` form.

- `MARKETING_VERSION` in `project.yml` is the app version and must be a three-part semantic version, for example `0.1.0`.
- Public release tags use the same version with a leading `v`, for example `v0.1.0`.
- `CURRENT_PROJECT_VERSION` remains the build number and should stay an integer that can be incremented independently.
- The automated release workflow rejects tags that do not match `vMAJOR.MINOR.PATCH`.
- The automated release workflow also rejects tags that do not match `CFBundleShortVersionString`.

The current release version is `0.1.2`, so the matching tag is:

```bash
git tag v0.1.2
git push origin v0.1.2
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

`make package-dmg` creates the standard drag-to-install disk image: `Voily.app` appears on the left, an `Applications` shortcut appears on the right, and `Resources/Release/dmg-background.png` is used as the default Finder background image. `Resources/Release/dmg-background-source.png` keeps the original high-resolution image, while `dmg-background.png` is the Finder-ready derivative sized for the small installer window. The command writes the Finder icon-view layout when `osascript` can access Finder; if the layout cannot be written in the current environment, the disk image still contains both items and remains installable. To temporarily replace the background image, set `VOILY_DMG_BACKGROUND_PATH`.

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
ARTIFACT=build/release/artifacts/Voily-0.1.2.dmg make notarize
ARTIFACT=build/release/artifacts/Voily-0.1.2.dmg make staple
ARTIFACT=build/release/artifacts/Voily-0.1.2.dmg make verify-release
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
git tag v0.1.2
git push origin v0.1.2
```

The workflow will:

1. Check out the tagged commit.
2. Verify the runner, signing identity, and `VOILY_NOTARY_PROFILE`.
3. Run `make release`.
4. Confirm the tag matches `CFBundleShortVersionString`.
5. Run `make package-dmg`.
6. Run `make notarize`, `make staple`, and `make verify-release`.
7. Generate `appcast.xml` and any Sparkle delta files from the notarized release artifacts.
8. Create the GitHub Release if it does not exist, or upload the dmg, `appcast.xml`, and delta files to the existing release with `--clobber`.

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
RELEASE_TAG="v0.1.2"
/tmp/voily-sparkle/bin/generate_appcast \
  --download-url-prefix "https://github.com/BubblePtr/Voily/releases/download/${RELEASE_TAG}/" \
  build/release/artifacts
```

The generated appcast and any generated delta files must be uploaded with the release artifacts. Keep `CFBundleVersion` (`CURRENT_PROJECT_VERSION`) increasing for every public release, because Sparkle uses it as the machine-readable update version. Keep `CFBundleShortVersionString` (`MARKETING_VERSION`) as the user-facing semantic version that matches the release tag.

## Recommended release notes checklist

Include these user-facing details in each release:

- Version number
- Minimum system version: macOS 14.0+
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
