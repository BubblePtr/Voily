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
ARTIFACT=build/release/artifacts/Voily-1.0-1.dmg make notarize
ARTIFACT=build/release/artifacts/Voily-1.0-1.dmg make staple
ARTIFACT=build/release/artifacts/Voily-1.0-1.dmg make verify-release
```

Notes:

- `make notarize` requires `VOILY_NOTARY_PROFILE`
- `make staple` works for `.app` and `.dmg`, not `.zip`
- if you want a stapled zip, staple the `.app` first and recreate the zip afterward

## 5. Publish to GitHub Releases

After verification succeeds:

1. Create a git tag for the release version.
2. Push the tag to GitHub.
3. Open a new GitHub Release.
4. Upload the notarized `.dmg`.
5. Add release notes, minimum macOS version, and first-launch permission guidance.

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
