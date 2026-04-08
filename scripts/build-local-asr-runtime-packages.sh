#!/usr/bin/env bash
set -euo pipefail
export COPYFILE_DISABLE=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_ROOT="${SRC_ROOT:-/tmp/voily-runtime-src}"
BUILD_ROOT="${BUILD_ROOT:-/tmp/voily-runtime-build}"
DIST_ROOT="${DIST_ROOT:-$ROOT_DIR/dist/local-asr}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"

require_tool() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "missing required tool: $tool" >&2
    exit 1
  fi
}

prepare_sources() {
  mkdir -p "$SRC_ROOT"

  if [[ ! -d "$SRC_ROOT/SenseVoice.cpp/.git" ]]; then
    git clone --recursive https://github.com/lovemefan/SenseVoice.cpp.git "$SRC_ROOT/SenseVoice.cpp"
  fi
}

build_sensevoice() {
  cmake -S "$SRC_ROOT/SenseVoice.cpp" -B "$BUILD_ROOT/SenseVoice.cpp" -DGGML_METAL=ON -DGGML_BLAS=ON
  cmake --build "$BUILD_ROOT/SenseVoice.cpp" -j "$JOBS"
}

reset_dir() {
  local dir="$1"
  rm -rf "$dir"
  mkdir -p "$dir"
}

strip_rpaths() {
  local binary="$1"
  while IFS= read -r path; do
    install_name_tool -delete_rpath "$path" "$binary"
  done < <(otool -l "$binary" | awk '
    $1 == "cmd" && $2 == "LC_RPATH" { in_rpath = 1; next }
    in_rpath && $1 == "path" { print $2; in_rpath = 0 }
  ')
}

set_local_runtime_rpaths() {
  local binary="$1"
  local runtime_path="$2"
  strip_rpaths "$binary"
  install_name_tool -add_rpath "$runtime_path" "$binary"
}

copy_sensevoice_runtime() {
  local stage_dir="$1"
  local runtime_dir="$stage_dir/runtime"
  reset_dir "$runtime_dir"

  cp "$BUILD_ROOT/SenseVoice.cpp/bin/sense-voice-main" "$runtime_dir/"
  cp "$BUILD_ROOT/SenseVoice.cpp/bin/ggml-metal.metal" "$runtime_dir/"
  cp "$BUILD_ROOT/SenseVoice.cpp/lib/libggml.dylib" "$runtime_dir/"
  cp "$BUILD_ROOT/SenseVoice.cpp/lib/libggml-base.dylib" "$runtime_dir/"
  cp "$BUILD_ROOT/SenseVoice.cpp/lib/libggml-cpu.dylib" "$runtime_dir/"
  cp "$BUILD_ROOT/SenseVoice.cpp/lib/libggml-blas.dylib" "$runtime_dir/"
  cp "$BUILD_ROOT/SenseVoice.cpp/lib/libggml-metal.dylib" "$runtime_dir/"

  set_local_runtime_rpaths "$runtime_dir/sense-voice-main" "@executable_path"
  for dylib in "$runtime_dir"/*.dylib; do
    set_local_runtime_rpaths "$dylib" "@loader_path"
  done
}

write_checksums() {
  local zip_path="$1"
  shasum -a 256 "$zip_path" > "$zip_path.sha256"
}

zip_stage() {
  local stage_dir="$1"
  local zip_path="$2"
  rm -f "$zip_path" "$zip_path.sha256"
  ditto --norsrc -c -k --keepParent "$stage_dir/runtime" "$zip_path"
  write_checksums "$zip_path"
}

sha_value() {
  awk '{ print $1 }' "$1"
}

write_manifest() {
  local manifest_path="$DIST_ROOT/manifest.local.json"
  local sensevoice_sha
  sensevoice_sha="$(sha_value "$DIST_ROOT/sensevoice/macos-arm64/sensevoice-runtime.zip.sha256")"

  cat > "$manifest_path" <<EOF
{
  "senseVoice": {
    "runtimePackageURL": "https://downloads.example.com/local-asr/sensevoice/macos-arm64/sensevoice-runtime.zip",
    "runtimeSHA256": "$sensevoice_sha",
    "executableRelativePath": "runtime/sense-voice-main",
    "modelDownloadURL": "https://huggingface.co/lovemefan/sense-voice-gguf/resolve/main/sense-voice-small-q4_k.gguf?download=true",
    "modelRelativePath": "models/sense-voice-small-q4_k.gguf"
  }
}
EOF
}

package_runtime() {
  local provider="$1"
  local arch_dir="$DIST_ROOT/$provider/macos-arm64"
  local stage_dir="$arch_dir/package"

  mkdir -p "$arch_dir"
  reset_dir "$stage_dir"

  case "$provider" in
    sensevoice)
      copy_sensevoice_runtime "$stage_dir"
      zip_stage "$stage_dir" "$arch_dir/sensevoice-runtime.zip"
      ;;
    *)
      echo "unknown provider: $provider" >&2
      exit 1
      ;;
  esac
}

main() {
  require_tool git
  require_tool cmake
  require_tool install_name_tool
  require_tool ditto
  require_tool shasum

  mkdir -p "$BUILD_ROOT" "$DIST_ROOT"
  prepare_sources
  build_sensevoice
  package_runtime sensevoice
  write_manifest

  echo "runtime packages written to $DIST_ROOT"
}

main "$@"
