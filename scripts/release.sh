#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${VOILY_PROJECT_PATH:-$ROOT_DIR/Voily.xcodeproj}"
SCHEME="${VOILY_SCHEME:-Voily}"
APP_NAME="${VOILY_APP_NAME:-Voily}"
RELEASE_ROOT="${VOILY_RELEASE_DIR:-$ROOT_DIR/build/release}"
DERIVED_DATA_PATH="${VOILY_DERIVED_DATA_PATH:-$RELEASE_ROOT/DerivedData}"
ARCHIVE_PATH="${VOILY_ARCHIVE_PATH:-$RELEASE_ROOT/${APP_NAME}.xcarchive}"
EXPORT_PATH="${VOILY_EXPORT_PATH:-$RELEASE_ROOT/export}"
APP_PATH="${VOILY_APP_PATH:-$RELEASE_ROOT/${APP_NAME}.app}"
ARTIFACTS_DIR="${VOILY_ARTIFACTS_DIR:-$RELEASE_ROOT/artifacts}"
EXPECTED_BUNDLE_ID="${VOILY_EXPECTED_BUNDLE_ID:-dev.kieranzhang.voily}"
DEFAULT_NOTARY_PROFILE="${VOILY_NOTARY_PROFILE:-${NOTARY_PROFILE:-}}"
EXPORT_OPTIONS_PLIST="${VOILY_EXPORT_OPTIONS_PLIST:-$RELEASE_ROOT/ExportOptions.plist}"

log() {
  printf "==> %s\n" "$*"
}

note() {
  printf "note: %s\n" "$*"
}

die() {
  printf "error: %s\n" "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

ensure_release_dirs() {
  mkdir -p "$RELEASE_ROOT" "$ARTIFACTS_DIR" "$EXPORT_PATH"
}

ensure_app() {
  [[ -d "$APP_PATH" ]] || archive_app
}

app_info_value() {
  local key="$1"
  /usr/libexec/PlistBuddy -c "Print :$key" "$APP_PATH/Contents/Info.plist"
}

artifact_stem() {
  local version build
  version="$(app_info_value CFBundleShortVersionString)"
  build="$(app_info_value CFBundleVersion)"
  printf "%s-%s-%s" "$APP_NAME" "$version" "$build"
}

default_zip_path() {
  printf "%s/%s.zip" "$ARTIFACTS_DIR" "$(artifact_stem)"
}

default_dmg_path() {
  printf "%s/%s.dmg" "$ARTIFACTS_DIR" "$(artifact_stem)"
}

discover_artifact_signing_identity() {
  if [[ -n "${VOILY_DMG_SIGN_IDENTITY:-}" ]]; then
    printf "%s\n" "$VOILY_DMG_SIGN_IDENTITY"
    return 0
  fi

  if [[ -n "${VOILY_CODE_SIGN_IDENTITY:-}" ]]; then
    printf "%s\n" "$VOILY_CODE_SIGN_IDENTITY"
    return 0
  fi

  if [[ ! -d "$APP_PATH" ]]; then
    return 0
  fi

  codesign -dvvv "$APP_PATH" 2>&1 | sed -n 's/^Authority=//p' | head -n 1
}

archive_app() {
  require_cmd xcodebuild
  require_cmd ditto

  ensure_release_dirs
  rm -rf "$ARCHIVE_PATH" "$APP_PATH" "$EXPORT_PATH"
  mkdir -p "$EXPORT_PATH"

  local cmd=(
    xcodebuild
    -project "$PROJECT_PATH"
    -scheme "$SCHEME"
    -configuration Release
    -derivedDataPath "$DERIVED_DATA_PATH"
    -archivePath "$ARCHIVE_PATH"
    archive
  )

  if [[ -n "${VOILY_DEVELOPMENT_TEAM:-}" ]]; then
    cmd+=("DEVELOPMENT_TEAM=${VOILY_DEVELOPMENT_TEAM}")
  fi

  log "Archiving $APP_NAME (Release)"
  "${cmd[@]}"

  generate_export_options_plist
  export_archive

  local exported_app="$EXPORT_PATH/$APP_NAME.app"
  [[ -d "$exported_app" ]] || die "Export completed but app bundle was not found at $exported_app"

  ditto "$exported_app" "$APP_PATH"
  log "Exported app bundle to $APP_PATH"
}

generate_export_options_plist() {
  local team_id="${VOILY_DEVELOPMENT_TEAM:-$(security find-certificate -c 'Developer ID Application' -p 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU=\\([^,/]*\\).*/\\1/p' | head -n 1)}"
  local signing_style="automatic"

  cat >"$EXPORT_OPTIONS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>$signing_style</string>
EOF

  if [[ -n "$team_id" ]]; then
    cat >>"$EXPORT_OPTIONS_PLIST" <<EOF
  <key>teamID</key>
  <string>$team_id</string>
EOF
  fi

  if [[ -n "${VOILY_CODE_SIGN_IDENTITY:-}" ]]; then
    cat >>"$EXPORT_OPTIONS_PLIST" <<EOF
  <key>signingStyle</key>
  <string>manual</string>
  <key>signingCertificate</key>
  <string>${VOILY_CODE_SIGN_IDENTITY}</string>
EOF
  fi

  cat >>"$EXPORT_OPTIONS_PLIST" <<EOF
</dict>
</plist>
EOF
}

export_archive() {
  require_cmd xcodebuild

  log "Exporting archive for developer-id distribution"
  xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

  local archived_app="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
  [[ -d "$archived_app" ]] || die "Archive completed but app bundle was not found at $archived_app"
}

package_zip() {
  require_cmd ditto

  ensure_app
  ensure_release_dirs

  local zip_path="${1:-$(default_zip_path)}"
  rm -f "$zip_path"

  log "Packaging zip archive"
  ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$zip_path"
  log "Created $zip_path"
}

package_dmg() {
  require_cmd ditto
  require_cmd hdiutil
  require_cmd codesign

  ensure_app
  ensure_release_dirs

  local dmg_path="${1:-$(default_dmg_path)}"
  local staging_dir="$RELEASE_ROOT/dmg-staging"
  local signing_identity=""

  rm -rf "$staging_dir"
  rm -f "$dmg_path"
  mkdir -p "$staging_dir"

  ditto "$APP_PATH" "$staging_dir/$APP_NAME.app"

  log "Packaging dmg archive"
  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$staging_dir" \
    -format UDZO \
    "$dmg_path"

  signing_identity="$(discover_artifact_signing_identity)"
  if [[ -n "$signing_identity" ]]; then
    log "Signing dmg with $signing_identity"
    if [[ "$signing_identity" == Developer\ ID\ Application:* ]]; then
      codesign --force --sign "$signing_identity" --timestamp "$dmg_path"
    else
      codesign --force --sign "$signing_identity" "$dmg_path"
    fi
  else
    note "No signing identity found for dmg. Continuing with an unsigned disk image."
  fi

  rm -rf "$staging_dir"
  log "Created $dmg_path"
}

resolve_default_artifact() {
  ensure_app

  local dmg_path zip_path
  dmg_path="$(default_dmg_path)"
  zip_path="$(default_zip_path)"

  if [[ -f "$dmg_path" ]]; then
    printf "%s\n" "$dmg_path"
    return 0
  fi

  if [[ -f "$zip_path" ]]; then
    printf "%s\n" "$zip_path"
    return 0
  fi

  package_dmg "$dmg_path" >/dev/null
  printf "%s\n" "$dmg_path"
}

notarize_artifact() {
  require_cmd xcrun

  local artifact_path="${1:-}"
  local profile="${2:-$DEFAULT_NOTARY_PROFILE}"

  if [[ -z "$artifact_path" ]]; then
    artifact_path="$(resolve_default_artifact)"
  fi

  [[ -f "$artifact_path" || -d "$artifact_path" ]] || die "Artifact not found: $artifact_path"
  [[ -n "$profile" ]] || die "Set VOILY_NOTARY_PROFILE (or NOTARY_PROFILE) to a notarytool keychain profile before notarizing."

  log "Submitting $artifact_path for notarization"
  xcrun notarytool submit "$artifact_path" --keychain-profile "$profile" --wait
}

staple_artifact() {
  require_cmd xcrun

  local artifact_path="${1:-$APP_PATH}"
  [[ -f "$artifact_path" || -d "$artifact_path" ]] || die "Artifact not found: $artifact_path"

  if [[ "$artifact_path" == *.zip ]]; then
    die "Cannot staple a zip archive. Staple the .app or .dmg, then recreate the zip."
  fi

  log "Stapling $artifact_path"
  xcrun stapler staple -v "$artifact_path"
}

verify_release() {
  require_cmd codesign
  require_cmd spctl
  require_cmd xcrun

  ensure_app

  local artifact_path="${1:-}"
  local bundle_id codesign_output spctl_output artifact_spctl_args

  bundle_id="$(app_info_value CFBundleIdentifier)"
  [[ "$bundle_id" == "$EXPECTED_BUNDLE_ID" ]] || die "Bundle identifier mismatch: expected $EXPECTED_BUNDLE_ID, found $bundle_id"

  log "Running codesign verification for $APP_PATH"
  codesign --verify --deep --strict "$APP_PATH"
  codesign_output="$(codesign -dvvv "$APP_PATH" 2>&1)"

  if ! grep -q "flags=.*runtime" <<<"$codesign_output"; then
    die "Hardened runtime is not enabled on the Release app bundle."
  fi

  printf "%s\n" "$codesign_output"

  log "Reading app entitlements"
  codesign -d --entitlements :- "$APP_PATH" 2>&1 || true

  log "Assessing Gatekeeper status for app bundle"
  if spctl_output="$(spctl -a -vv "$APP_PATH" 2>&1)"; then
    printf "%s\n" "$spctl_output"
  else
    note "Gatekeeper rejected the current app bundle. Public distribution still requires a Developer ID Application signature and notarization."
    printf "%s\n" "$spctl_output"
  fi

  if [[ -n "$artifact_path" ]]; then
    [[ -f "$artifact_path" || -d "$artifact_path" ]] || die "Artifact not found: $artifact_path"

    if [[ "$artifact_path" == *.dmg || "$artifact_path" == *.pkg ]]; then
      artifact_spctl_args=(-a -vv -t install "$artifact_path")
    else
      artifact_spctl_args=(-a -vv "$artifact_path")
    fi

    if [[ "$artifact_path" == *.dmg || "$artifact_path" == *.pkg || "$artifact_path" == *.app ]]; then
      log "Validating stapled ticket for artifact $artifact_path"
      xcrun stapler validate "$artifact_path"
    fi

    log "Assessing Gatekeeper status for artifact $artifact_path"
    if spctl_output="$(spctl "${artifact_spctl_args[@]}" 2>&1)"; then
      printf "%s\n" "$spctl_output"
    else
      note "Gatekeeper rejected $artifact_path. Check whether the artifact was notarized and stapled, and use the correct spctl assessment type for the file format."
      printf "%s\n" "$spctl_output"
    fi
  fi

  log "Release artifact summary"
  printf "Bundle identifier: %s\n" "$bundle_id"
  printf "Version: %s\n" "$(app_info_value CFBundleShortVersionString)"
  printf "Build: %s\n" "$(app_info_value CFBundleVersion)"
  printf "App path: %s\n" "$APP_PATH"
  printf "Archive path: %s\n" "$ARCHIVE_PATH"
}

usage() {
  cat <<'EOF'
Usage: ./scripts/release.sh <command> [artifact-path]

Commands:
  archive        Archive the Release build and export Voily.app to build/release/
  package-zip    Create a zip archive from the archived app bundle
  package-dmg    Create a dmg archive from the archived app bundle
  notarize       Submit an artifact to Apple notary service
  staple         Staple a notarization ticket to a .app or .dmg
  verify         Verify bundle id, hardened runtime, codesign, and Gatekeeper status

Environment:
  VOILY_CODE_SIGN_IDENTITY   Optional explicit signing identity for xcodebuild archive
  VOILY_DEVELOPMENT_TEAM     Optional development team override for xcodebuild archive
  VOILY_NOTARY_PROFILE       Required for notarize; maps to a notarytool keychain profile
  VOILY_EXPECTED_BUNDLE_ID   Override the expected bundle identifier (default: dev.kieranzhang.voily)
EOF
}

main() {
  local command="${1:-}"

  case "$command" in
    archive)
      archive_app
      ;;
    package-zip)
      package_zip "${2:-}"
      ;;
    package-dmg)
      package_dmg "${2:-}"
      ;;
    notarize)
      notarize_artifact "${2:-}"
      ;;
    staple)
      staple_artifact "${2:-}"
      ;;
    verify)
      verify_release "${2:-}"
      ;;
    ""|-h|--help|help)
      usage
      ;;
    *)
      usage
      die "Unknown command: $command"
      ;;
  esac
}

main "$@"
