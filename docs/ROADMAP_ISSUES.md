# Voily Pre-launch Issue Backlog

This backlog breaks `docs/ROADMAP.md` into issue-sized tasks for a Codex Server executor that usually runs in a workspace sandbox.

These labels assume the issue workspace has already been provisioned with a real Voily repository checkout and the baseline tools needed by that issue, such as Xcode, SwiftPM package resolution, dependency cache, and any documented local build prerequisites. If the worker starts in an empty directory or without the required toolchain, classify that as an environment blocker before attempting the issue.

Use the `Sandbox fit` field to decide routing:

- `sandbox-first`: the executor can implement and validate most of the issue inside the repository.
- `sandbox + manual verify`: the executor can implement the repository change, but final acceptance needs a real macOS app run, real permission flow, real model download, real audio input, or live network.
- `human-owned`: the main work depends on external account, signing, runner, release, marketing, or community setup outside the workspace.

## Issue 1: Add tag-driven release workflow

Sandbox fit: `sandbox-first`

Scope:
- Add `.github/workflows/release.yml`.
- Trigger on pushed `v*` tags.
- Run on `self-hosted`, `macOS`, `voily-release`.
- Reuse `make release`, `make package-dmg`, `make notarize`, `make staple`, and `make verify-release`.
- Validate tag version against `CFBundleShortVersionString`.
- Detect `-beta.` and `-rc.` tags as prereleases.
- Fail if the GitHub Release already exists instead of overwriting it.

Automatic validation:
- YAML parses successfully.
- Workflow contains the expected trigger, runner labels, release commands, version check, prerelease check, and single `.dmg` artifact upload path.
- `git diff --check` passes.

Manual validation:
- Push a prerelease tag on the self-hosted release runner and confirm a notarized `.dmg` appears in GitHub Releases.
- Push or simulate a mismatched tag/app version and confirm release creation is blocked.

## Issue 2: Document release runner and tag rules

Sandbox fit: `sandbox-first`

Scope:
- Update `docs/releasing.md`.
- Document the self-hosted runner labels and runner prerequisites.
- Document stable and prerelease tag formats.
- Keep local release commands as the fallback debugging path.
- Explain that signing and notarization state must already exist on the runner.

Automatic validation:
- Docs mention `self-hosted`, `macOS`, `voily-release`, `VOILY_NOTARY_PROFILE`, `vX.Y.Z`, `vX.Y.Z-beta.N`, and `vX.Y.Z-rc.N`.
- `git diff --check` passes.

Manual validation:
- Release operator confirms the runner setup instructions match the actual release machine.

## Issue 3: Add local model download progress state

Sandbox fit: `sandbox-first`

Scope:
- Extend `ManagedASRModelStore` so install state exposes structured progress for local providers: bytes downloaded, total bytes if known, percent if derivable, transfer speed, and estimated remaining time.
- Keep install state provider-scoped and limit the code change to `ManagedASRModelStore` plus its direct Settings/UI consumers; do not refactor provider abstractions or cloud provider readiness.
- Replace the current string-only installing state with a structured progress-carrying state rather than layering more parsing onto display strings.
- Preserve current install, uninstall, and completion semantics for local providers aside from the new progress data.
- If download plumbing must change to surface progress, use the smallest built-in `URLSession`-based approach that fits the existing store; do not add third-party download dependencies or a standalone download framework.

Automatic validation:
- Unit tests cover progress formatting, unknown content length, completed state, cancellation, and failed download state.
- `xcodebuild test -scheme Voily -destination "platform=macOS" -only-testing:VoilyTests/ManagedASRModelStoreTests` passes, or if that test target does not exist yet, the issue must add the smallest focused test file that exercises `ManagedASRModelStore` directly and run it explicitly.
- `git diff --check` passes.

Manual validation:
- A real SenseVoice download shows progress updates in the app without regressing installed/not-installed behavior.

## Issue 4: Add retry and clearer local model install errors

Sandbox fit: `sandbox-first`

Scope:
- Add bounded retry behavior for transient model download failures.
- Surface clear user-facing error messages for network failure, HTTP failure, cancellation, incomplete install, and filesystem failure.
- Keep retry behavior explicit and low-complexity.

Automatic validation:
- Unit tests cover retry count, non-retryable failures, cancellation, and final failure message.
- Targeted `xcodebuild test` passes.
- `git diff --check` passes.

Manual validation:
- Interrupt or block a real download and confirm the Settings UI shows a useful failure state.

## Issue 5: Add provider-scoped local model install prompt

Sandbox fit: `sandbox + manual verify`

Scope:
- Prompt only when the selected ASR provider is local and that provider is not installed.
- Do not block cloud providers.
- Do not use a global "model missing" gate.
- Reuse existing `ManagedASRModelStore` state.

Automatic validation:
- Unit or view-model tests cover local not-installed, local installed, cloud selected, and provider switch cases.
- `make build` succeeds.
- `git diff --check` passes.

Manual validation:
- Run the app and confirm the prompt appears only for the local provider path.

## Issue 6: Suppress unstable first partial text

Sandbox fit: `sandbox-first`

Scope:
- Reduce false first partial display such as a leading "嗯" during silence.
- Add a narrowly scoped stabilization rule that only affects the first outward-facing partial shown during a single capture session; do not change final transcript commit behavior.
- Treat obviously unstable first partials as suppressible, but keep the first non-filler partial prompt when it is likely to be real speech.
- Prefer implementing the rule inside the existing `ASRCaptureSession` / transcript-accumulator path; do not retune the default provider-independent `PartialTranscriptDisplayThrottle` as part of this issue unless a failing test proves that layer is the real source of the bug.
- Keep provider-specific partial semantics inside the existing `ASRCaptureSession` and accumulator boundaries.

Automatic validation:
- Unit tests cover first partial suppression, second partial confirmation, non-filler first partial, repeated partials, and final text preservation.
- `xcodebuild test -scheme Voily -destination "platform=macOS" -only-testing:VoilyTests/ASRCaptureSessionTests` passes.
- `git diff --check` passes.

Manual validation:
- Record silence and confirm the overlay no longer immediately shows a lone "嗯".
- Record normal speech and confirm the first real words still appear promptly.

## Issue 7: Evaluate partial display timing and overlay responsiveness

Sandbox fit: `sandbox + manual verify`

Scope:
- Review `PartialTranscriptDisplayThrottle` behavior and tune only if tests or manual audio runs justify it.
- Keep the default display throttle provider-independent.
- Avoid provider-specific UI debounce logic.

Automatic validation:
- Unit tests cover throttle timing, duplicate partials, pending text flush, and rapid updates.
- Targeted ASR capture-session tests pass.
- `git diff --check` passes.

Manual validation:
- Run streaming providers with real audio and confirm the overlay feels responsive without showing unstable noise.

## Issue 8A: Write repo-side speech enhancement research note

Sandbox fit: `sandbox-first`

Scope:
- Create a short evaluation note for competing-speaker suppression and speech enhancement options.
- Ground the note in the current capture path and ASR provider boundaries.
- Compare app-layer filtering, platform voice processing, provider-side features, and no-change baseline.
- Explicitly avoid treating VAD or low-pass filtering as denoise.
- Define what evidence the manual background-speech evaluation must collect before any implementation starts.

Automatic validation:
- Add a doc under `docs/superpowers/specs/` or `docs/decisions/` with options, risks, and a recommendation.
- `git diff --check` passes.

Manual validation:
- Maintainer confirms the recommendation matches the intended product bar before a speech-enhancement implementation issue is opened.

## Issue 8B: Manually evaluate background-speech capture

Sandbox fit: `human-owned`

Scope:
- Test real background-speech scenarios with the current app and target microphones.
- Capture whether background speakers affect partial text, final text, or both.
- Compare local SenseVoice and the intended cloud providers if configured.
- Decide whether the launch blocker is first-partial stability, foreground-speaker separation, model/provider choice, or no code change.

Automatic validation:
- If observations are written back into the repo, markdown checks pass.

Manual validation:
- Real macOS app run records enough examples to decide whether speech enhancement work is needed before launch.

## Issue 9: Add first-launch onboarding shell

Sandbox fit: `sandbox + manual verify`

Scope:
- Add first-launch onboarding state.
- Show onboarding on first app launch.
- Recommend local SenseVoice first.
- Allow users to skip model download.
- Do not block entry into the main app.

Automatic validation:
- Tests cover first launch, completed onboarding, skipped onboarding, and relaunch behavior.
- `make build` succeeds.
- `git diff --check` passes.

Manual validation:
- Fresh app data shows onboarding once.
- Skipping onboarding enters the app without forced actions.

## Issue 10: Integrate PermissionFlow for Accessibility guidance

Sandbox fit: `sandbox + manual verify`

Scope:
- Add `PermissionFlow` only for Accessibility guidance.
- Keep microphone permission on the native system request path.
- Preserve existing `PermissionCoordinator` responsibility for checking and polling trust state.
- Do not introduce `PermissionFlow` as the global permission abstraction.

Automatic validation:
- Project resolves the Swift package.
- `make build` succeeds.
- Tests or lightweight seams cover Accessibility trusted/untrusted state transitions where practical.
- `git diff --check` passes.

Environment notes:
- Package resolution depends on the worker having Xcode/SwiftPM and either network access or a usable package cache.
- If package resolution fails because the issue workspace lacks toolchain, network, or cache, classify it as an environment blocker rather than a product failure.

Manual validation:
- Run the app on macOS and confirm the Accessibility flow opens the correct System Settings path and returns to Voily once trusted.

## Issue 11: Add dashboard reminder for incomplete setup

Sandbox fit: `sandbox + manual verify`

Scope:
- Add a non-blocking reminder at the top of the dashboard when Accessibility is missing or the recommended local model is not installed.
- Show the reminder once per app launch when setup is incomplete.
- Provide actions to open Accessibility guidance and start local model download.
- Allow dismissal for the current launch.

Automatic validation:
- View-model or state tests cover missing Accessibility, missing model, both missing, all complete, and dismissed-for-launch.
- SwiftUI preview or snapshot-friendly view state exists if the repo uses it.
- `make build` succeeds.
- `git diff --check` passes.

Manual validation:
- Launch with incomplete setup and confirm the dashboard reminder appears without blocking app use.

## Issue 12: Add cloud provider follow-up guidance

Sandbox fit: `sandbox-first`

Scope:
- After local-first onboarding, provide a clear Settings path for configuring cloud providers.
- Do not promise free trial quota.
- Keep user-owned API keys as the cloud provider model.
- Update README and README_CN if the onboarding wording changes user setup expectations.

Automatic validation:
- Docs and Settings copy avoid "free trial" language.
- `make build` succeeds if UI copy changes.
- `git diff --check` passes.

Manual validation:
- User can find cloud provider setup after completing or skipping local onboarding.

## Issue 13: Build landing page content plan

Sandbox fit: `human-owned`

Scope:
- Decide whether the landing page lives in this repo or a separate website repo.
- Prepare product copy, screenshots, demo recording plan, download CTA, and install guidance.
- Keep release artifact links aligned with GitHub Releases.

Automatic validation:
- If content is stored in this repo, markdown or site files pass formatting/build checks.

Manual validation:
- Capture real app screenshots and demo videos.
- Publish the site and verify download links.

## Issue 14: Update user and contributor docs

Sandbox fit: `sandbox-first`

Scope:
- Update README and README_CN with current setup flow.
- Add or update CONTRIBUTING.md.
- Add GitHub issue templates if this repo will use GitHub Issues as the public intake path.
- Document provider configuration and local model storage behavior.

Automatic validation:
- Docs mention macOS 14+, microphone permission, Accessibility permission, local SenseVoice model download, and cloud provider API key requirements.
- `git diff --check` passes.

Manual validation:
- A fresh user can follow the docs to install, grant permissions, download or skip the local model, and start dictation.

## Issue 15: Launch feedback and bug triage process

Sandbox fit: `human-owned`

Scope:
- Define beta intake channels.
- Define high-frequency bug triage labels.
- Prepare Product Hunt, 即刻, and 少数派 launch checklist.
- Decide who validates incoming reports on real macOS versions and hardware.

Automatic validation:
- If templates or docs are stored in this repo, markdown checks pass.

Manual validation:
- Beta users can submit issues.
- Maintainer can reproduce or classify reports with enough environment detail.
