# Voily macOS 14 Compatibility Design

## Goal

Lower the app-wide deployment target from macOS 26 to macOS 14 without changing the product shape:

- keep the current app structure and SwiftUI scene setup
- keep the floating voice capsule overlay behavior and interaction model
- remove Liquid Glass dependencies and replace them with a macOS 14-safe visual treatment
- preserve existing settings window flow, overlay animations, and app-level behavior unless compatibility work requires a targeted fallback

This change is a compatibility and presentation refactor, not a feature redesign.

## Scope

In scope:

- change deployment target and minimum system version metadata from macOS 26.0 to macOS 14.0
- remove `@available(macOS 26.0, *)` gates that only exist because of current deployment targeting
- remove `GlassEffectContainer` and `.glassEffect(...)` usage from the overlay
- remove or replace scene modifiers that are unavailable on macOS 14
- fix compile-time fallout from the lower deployment target across app, overlay, and settings UI
- update README minimum-version statements

Out of scope:

- redesigning the overlay layout, animation timing, or interaction model
- changing settings information architecture
- introducing a separate compatibility abstraction layer across the entire codebase
- changing ASR, text processing, permissions, or status item behavior except where required for compile/runtime compatibility

## Compatibility Baseline

Known API boundaries relevant to the current code:

- `Window(...)` scene is available on macOS 13+
- `.defaultSize(width:height:)` is available on macOS 13+
- `NavigationSplitView` is available on macOS 13+
- `.navigationSubtitle(...)` is available on macOS 11+
- `.defaultLaunchBehavior(...)` is available on macOS 15+ and must not remain in a macOS 14 target
- `GlassEffectContainer` and `.glassEffect(...)` are part of the current macOS 26-only visual path and must be removed

Because macOS 14 is the new floor, the implementation should prefer direct macOS 14-compatible code over scattered `if #available` checks. Availability checks should only remain where a genuinely newer API is still worth keeping.

## Design

### 1. Project-level target change

Update all project metadata that currently declares macOS 26:

- Xcode deployment target entries
- `LSMinimumSystemVersion` in `Config/Info.plist`
- README and README_CN version statements and badges

Expected result: the project advertises and builds for macOS 14.0+ consistently.

### 2. App scene strategy

Keep the existing dedicated `Window("Voily", id: ...)` scene.

Retain:

- `Window("Voily", id: SettingsWindowSceneID.settings)`
- `.defaultSize(width: 1120, height: 760)`

Remove:

- `.defaultLaunchBehavior(.presented)`

Reasoning:

- the scene type itself is already compatible with macOS 14
- the unsupported part is only the launch-behavior modifier
- removing that modifier is a smaller and safer change than restructuring the app around a different scene type

Runtime expectation:

- explicit window showing via existing controller methods remains the source of truth
- app startup behavior may differ slightly from macOS 26 defaults, so this must be verified manually after the change

### 3. Overlay visual fallback

Keep the current overlay controller and content structure:

- `NSPanel` container
- width calculation
- show/hide frame animation
- waveform animation
- sliding preview text
- confirm/cancel actions
- highlight pass

Replace only the outer visual shell.

Current macOS 26-only shell:

- `GlassEffectContainer`
- `.glassEffect(...)`
- glass-oriented chrome styling

New macOS 14 shell:

- a capsule background using a dark translucent fill
- a subtle gradient or material-like depth cue implemented with standard SwiftUI/AppKit-safe primitives
- a light top-edge border/highlight to keep the capsule readable on varied backgrounds
- keep the existing flowing highlight if it compiles cleanly and still reads well without glass
- keep the current shadow, adjusted only if the new shell needs slightly more separation

Design intent:

- preserve the compact, floating, premium look
- avoid pretending to be Liquid Glass on systems that do not support it
- favor stable translucency and contrast over novelty

### 4. Availability cleanup

Remove file/type-level `@available(macOS 26.0, *)` annotations where the underlying implementation is macOS 14-safe after the visual/API changes.

Do not replace blanket 26.0 annotations with blanket 14.0 annotations unless they clarify a real boundary. With a macOS 14 deployment target, most of these declarations should become unnecessary.

If a specific API still requires a newer version after the refactor, isolate that call site rather than re-applying wide availability gates to whole files.

### 5. Validation

Validation must focus on both compile success and behavior:

- build the app for the macOS 14 target in the current Xcode project
- verify the settings window scene still opens and reopens correctly
- verify the overlay still appears, resizes, and dismisses correctly
- verify the overlay remains legible on mixed backgrounds after the glass removal
- verify documentation and bundle metadata now state macOS 14.0+

## Risks and Mitigations

### Risk: startup window behavior shifts after removing `defaultLaunchBehavior`

Mitigation:

- keep the current explicit show-window paths intact
- verify cold launch and app reopen manually
- if startup behavior regresses materially, add explicit startup window presentation in app/controller code instead of reintroducing newer scene APIs

### Risk: overlay looks flatter or heavier without Liquid Glass

Mitigation:

- preserve existing capsule proportions, highlight motion, and compact spacing
- use a restrained layered background plus border rather than a flat opaque pill
- adjust only the outer shell, not the content composition

### Risk: hidden 26-only usages remain elsewhere

Mitigation:

- lower the target, build, and address compiler errors systematically
- keep changes narrow and local rather than introducing broad compatibility wrappers up front

## Implementation Notes

Preferred execution order:

1. change deployment target and metadata
2. remove unsupported scene modifier
3. refactor overlay shell away from Liquid Glass
4. remove stale availability annotations
5. build and fix remaining compatibility errors
6. run targeted manual verification

This order keeps the compatibility errors visible early while avoiding unnecessary architectural churn.
