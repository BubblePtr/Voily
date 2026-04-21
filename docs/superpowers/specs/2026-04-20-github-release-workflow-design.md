# Voily GitHub Release Workflow Design

## Goal

Automate the existing local release flow with a tag-driven GitHub Actions workflow that runs on a self-hosted Mac mini and publishes a notarized `.dmg` to GitHub Releases.

This design intentionally reuses the current repository release entrypoints instead of creating a second CI-only release implementation.

## Scope

In scope:

- add a GitHub Actions workflow at `.github/workflows/release.yml`
- trigger releases from pushed tags matching `v*`
- run release jobs only on a dedicated self-hosted macOS runner
- reuse the existing release commands:
  - `make release`
  - `make package-dmg`
  - `ARTIFACT=... make notarize`
  - `ARTIFACT=... make staple`
  - `ARTIFACT=... make verify-release`
- create a GitHub Release automatically after the notarized artifact is verified
- upload the notarized `.dmg` as the public download artifact
- generate release notes automatically through GitHub
- mark `beta` and `rc` tags as prereleases

Out of scope:

- importing signing certificates into GitHub-hosted runners
- building a second manual-only release path in CI
- automatically changing app version metadata from the workflow
- uploading a `.zip` artifact in the first release workflow version
- adding an approval gate before publishing
- provisioning or configuring the self-hosted runner machine itself

## Chosen Approach

Use one tag-driven workflow and one release job on a dedicated self-hosted Mac mini.

Why this approach:

- the repository already has a working local release script in `scripts/release.sh`
- signing and notarization are simpler and more reliable when the machine already has the required keychain and `notarytool` setup
- the workflow stays small and production-friendly because GitHub Actions only orchestrates the existing release steps

Alternatives considered but not chosen for the first version:

- GitHub-hosted macOS runners with temporary certificate import
- separate build and publish jobs with artifact handoff
- manual dispatch plus a release approval gate

These can be added later if the release process needs stronger isolation, broader contributor access, or an approval checkpoint.

## Runner Baseline

The release workflow assumes one dedicated self-hosted runner with stable labels, for example:

- `self-hosted`
- `macOS`
- `voily-release`

The machine must already provide:

- Xcode and Xcode command line tools
- access to the repository checkout
- a usable `Developer ID Application` signing identity in the active keychain
- a working `notarytool` keychain profile exposed through `VOILY_NOTARY_PROFILE` or `NOTARY_PROFILE`

The workflow should treat this Mac mini as a release machine rather than a generic development host. The job must rely on the machine's existing keychain and not attempt to reconstruct signing state inside the workflow.

## Workflow Design

### 1. Triggering

The workflow triggers on:

- `push` tags matching `v*`

Examples:

- `v1.0.0`
- `v1.2.3-beta.1`
- `v1.2.3-rc.1`

Branch pushes and pull requests are not part of this workflow.

### 2. Concurrency and isolation

The workflow uses a release-specific concurrency group so only one release job can run at a time.

Reasoning:

- the release script writes to `build/release`
- notarization and packaging should not race across two tags
- serializing release jobs is simpler than making the current local release layout multi-run safe

At the start of the job, the workflow should remove any existing `build/release` directory so only the current release artifacts remain.

### 3. Build and package sequence

The workflow should execute the current release flow in this order:

1. `make release`
2. `make package-dmg`
3. detect the generated `.dmg` path under `build/release/artifacts/`
4. `ARTIFACT=<dmg-path> make notarize`
5. `ARTIFACT=<dmg-path> make staple`
6. `ARTIFACT=<dmg-path> make verify-release`

This sequence keeps the workflow aligned with the documented local release process in `docs/releasing.md`.

### 4. Version validation

Before publishing a GitHub Release, the workflow must confirm that the tag version matches the exported app version.

Validation rule:

- strip the leading `v` from the tag
- read `CFBundleShortVersionString` from `build/release/Voily.app/Contents/Info.plist`
- fail if those two values do not match exactly

`CFBundleVersion` is not tied to the tag format in the first version of this workflow. That keeps the workflow compatible with the current project build-number strategy.

### 5. Release type detection

The workflow derives the GitHub release type from the tag name:

- tags matching `vX.Y.Z` publish as normal releases
- tags containing `-beta.` or `-rc.` publish as prereleases

This keeps stable releases and preview releases separate without introducing extra workflow inputs.

### 6. GitHub Release publishing

After notarization and verification succeed, the workflow creates the GitHub Release and uploads the generated `.dmg`.

Release settings:

- title: tag name, for example `v1.2.3`
- autogenerated release notes: enabled
- artifact uploaded: notarized `.dmg`
- prerelease: determined from tag naming rules above

The workflow should fail rather than silently overwrite an existing release for the same tag.

## Failure Behavior

The job is intentionally linear and fail-fast.

If any step fails:

- stop the workflow immediately
- do not create a GitHub Release
- do not upload any public artifact

This avoids partially published states such as a GitHub Release that exists without a notarized payload.

The first version does not add extra debug-artifact uploads. The primary troubleshooting surface is the Actions log plus the preserved workspace on the self-hosted machine.

## Validation

Implementation is complete only when all of the following are true:

- the workflow syntax passes validation
- a self-hosted runner with the expected labels picks up the job
- a test prerelease tag such as `v1.0.0-beta.1` produces a GitHub prerelease with an uploaded notarized `.dmg`
- a stable tag such as `v1.0.0` produces a normal GitHub release
- a mismatched tag and app version cause the workflow to fail before release creation

## Risks and Mitigations

### Risk: the self-hosted Mac mini loses signing or notarization readiness

Mitigation:

- keep signing certificates and the `notarytool` profile configured directly on the runner machine
- use one dedicated release label so failures are isolated to the intended machine
- keep the workflow thin so release issues can be reproduced locally with the same `make` commands

### Risk: stale artifacts from a previous run are uploaded

Mitigation:

- serialize release jobs with `concurrency`
- delete `build/release` before starting a new release run
- resolve the artifact path only after the current `package-dmg` step completes

### Risk: version tags drift from the app bundle version

Mitigation:

- validate the pushed tag against `CFBundleShortVersionString`
- fail before GitHub Release creation if the values differ

### Risk: CI logic drifts from the local release process

Mitigation:

- keep `scripts/release.sh` as the only place that knows how to archive, package, notarize, staple, and verify
- limit the workflow to orchestration, version checks, and GitHub Release creation
