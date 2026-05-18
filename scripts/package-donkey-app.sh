#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/Donkey.app"
DMG_PATH="$ROOT_DIR/dist/Donkey.dmg"
DMG_ROOT="$ROOT_DIR/dist/DonkeyInstaller"
RUNTIME_PACKAGE_DIR="$ROOT_DIR/dist/LocalRuntimePackages"
RUNTIME_PACKAGE_VERSION="${DONKEY_RUNTIME_PACKAGE_VERSION:-0.3.0-runner}"
APP_VERSION="${DONKEY_APP_VERSION:-0.1.0}"
APP_BUILD="${DONKEY_APP_BUILD:-1}"
SPARKLE_FEED_URL="${DONKEY_SPARKLE_FEED_URL:-}"
SPARKLE_PUBLIC_ED_KEY="${DONKEY_SPARKLE_PUBLIC_ED_KEY:-}"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
BUILD_DIR="$ROOT_DIR/apps/Donkey"
EXECUTABLE="$BUILD_DIR/.build/release/Donkey"
CACHE_DIR="$BUILD_DIR/.build/package-cache"
RUNTIME_RUNNER_SOURCE="$ROOT_DIR/scripts/local-runtime-runners/donkey_runtime_runner.py"

mkdir -p "$CACHE_DIR/clang" "$CACHE_DIR/swiftpm" "$CACHE_DIR/home"
export CLANG_MODULE_CACHE_PATH="$CACHE_DIR/clang"
export SWIFTPM_CACHE_PATH="$CACHE_DIR/swiftpm"
export HOME="$CACHE_DIR/home"

cd "$BUILD_DIR"
echo "Compiling Donkey for Mac ..."
swift build -c release --product Donkey

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"
cp "$EXECUTABLE" "$MACOS_DIR/Donkey"

make_runtime_package() {
  local runtime_id="$1"
  local executable_name="$2"
  local model_id="$3"
  local role="$4"
  local model_url="${5:-}"
  local model_sha256="${6:-}"
  local model_filename="${7:-model.bin}"
  local requirements="${8:-}"
  local package_dir="$RUNTIME_PACKAGE_DIR/$runtime_id"
  local bin_dir="$package_dir/bin"
  local lib_dir="$package_dir/lib"
  local executable_path="$bin_dir/$executable_name"
  local runner_path="$lib_dir/donkey_runtime_runner.py"
  local requirements_path="$package_dir/requirements.txt"

  mkdir -p "$bin_dir" "$lib_dir"
  cp "$RUNTIME_RUNNER_SOURCE" "$runner_path"
  chmod 755 "$runner_path"
  cat > "$executable_path" <<EOF_RUNTIME
#!/usr/bin/env sh
SCRIPT_DIR="\$(CDPATH= cd -- "\$(dirname -- "\$0")" && pwd)"
PYTHON="\${DONKEY_RUNTIME_PYTHON:-python3}"
PACKAGE_DIR="\$(CDPATH= cd -- "\$SCRIPT_DIR/.." && pwd)"
export DONKEY_RUNTIME_ID="$runtime_id"
export DONKEY_RUNTIME_VERSION="$RUNTIME_PACKAGE_VERSION"
export DONKEY_MODEL_ID="$model_id"
export DONKEY_RUNTIME_ROLE="$role"
export DONKEY_MODEL_URL="$model_url"
export DONKEY_MODEL_SHA256="$model_sha256"
export DONKEY_MODEL_FILENAME="$model_filename"
export DONKEY_RUNTIME_PACKAGE_DIR="\$PACKAGE_DIR"
export DONKEY_RUNTIME_STATE_DIR="\${DONKEY_RUNTIME_STATE_DIR:-\$HOME/Library/Application Support/Donkey/LocalModelRuntimes/RuntimePython/$runtime_id}"
if ! command -v "\$PYTHON" >/dev/null 2>&1; then
  printf '{"status":"error","runtimeID":"%s","modelID":"%s","metadata":{"reason":"pythonRuntimeUnavailable","dependency":"python3"}}' "$runtime_id" "$model_id"
  exit 0
fi
exec "\$PYTHON" "\$SCRIPT_DIR/../lib/donkey_runtime_runner.py"
EOF_RUNTIME
  chmod 755 "$executable_path"
  if [ -n "$requirements" ]; then
    printf '%s\n' "$requirements" > "$requirements_path"
  fi

  local executable_sha
  local runner_sha
  local requirements_sha=""
  local requirements_manifest_entry=""
  executable_sha="$(shasum -a 256 "$executable_path" | awk '{print $1}')"
  runner_sha="$(shasum -a 256 "$runner_path" | awk '{print $1}')"
  if [ -f "$requirements_path" ]; then
    requirements_sha="$(shasum -a 256 "$requirements_path" | awk '{print $1}')"
    requirements_manifest_entry=",
    {
      \"relativePath\" : \"requirements.txt\",
      \"sha256\" : \"$requirements_sha\",
      \"isExecutable\" : false
    }"
  fi
  cat > "$package_dir/manifest.json" <<EOF_MANIFEST
{
  "runtimeID" : "$runtime_id",
  "runtimeVersion" : "$RUNTIME_PACKAGE_VERSION",
  "modelID" : "$model_id",
  "platform" : "macos",
  "architecture" : "$(uname -m | sed 's/aarch64/arm64/;s/x86_64/x86_64/')",
  "sidecarProtocolVersion" : "v1",
  "minimumDonkeyVersion" : "0.1.0",
  "executableRelativePath" : "bin/$executable_name",
  "files" : [
    {
      "relativePath" : "bin/$executable_name",
      "sha256" : "$executable_sha",
      "isExecutable" : true
    },
    {
      "relativePath" : "lib/donkey_runtime_runner.py",
      "sha256" : "$runner_sha",
      "isExecutable" : true
    }$requirements_manifest_entry
  ],
  "signature" : "bundled-runner-package",
  "signingKeyID" : "donkey-runner",
  "metadata" : {
    "runtime.package" : "donkey-runner-package",
    "modelWeightsBundled" : "false",
    "modelWeights.downloadURL" : "$model_url",
    "modelWeights.sha256" : "$model_sha256",
    "modelWeights.filename" : "$model_filename",
    "sidecar.role" : "$role"
  }
}
EOF_MANIFEST
}

rm -rf "$RUNTIME_PACKAGE_DIR"
mkdir -p "$RUNTIME_PACKAGE_DIR"
make_runtime_package "parakeet-transcriber" "donkey-parakeet-transcriber" "nvidia/parakeet-tdt-0.6b-v3" "voiceTranscription" "${DONKEY_PARAKEET_MODEL_URL:-}" "${DONKEY_PARAKEET_MODEL_SHA256:-}" "${DONKEY_PARAKEET_MODEL_FILENAME:-parakeet-model.bin}" $'huggingface_hub>=0.25,<1'
make_runtime_package "yolo-segmenter" "donkey-yolo-segmenter" "ultralytics/yolo26n-seg" "screenshotSegmentation" "${DONKEY_YOLO_MODEL_URL:-}" "${DONKEY_YOLO_MODEL_SHA256:-}" "${DONKEY_YOLO_MODEL_FILENAME:-yolo26n-seg.pt}" $'ultralytics>=8.3,<9\nopencv-python-headless>=4.10,<5'
make_runtime_package "ui-understander" "donkey-ui-understander" "local-ui-understander" "uiUnderstanding" "${DONKEY_UI_UNDERSTANDER_MODEL_URL:-}" "${DONKEY_UI_UNDERSTANDER_MODEL_SHA256:-}" "${DONKEY_UI_UNDERSTANDER_MODEL_FILENAME:-ui-understander-model.bin}"
make_runtime_package "local-llm" "donkey-local-llm" "${DONKEY_LOCAL_LLM_MODEL_ID:-qwen3:8b}" "localLLM" "" "" "${DONKEY_LOCAL_LLM_MODEL_FILENAME:-ollama-qwen3-8b}"
cp -R "$RUNTIME_PACKAGE_DIR" "$RESOURCES_DIR/LocalRuntimePackages"

RESOURCE_BUNDLE="$(find "$BUILD_DIR/.build" -path "*/release/Donkey_Donkey.bundle" -type d | head -n 1 || true)"
if [ -n "$RESOURCE_BUNDLE" ]; then
  cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
elif [ -d "$BUILD_DIR/.build/release/Donkey_Donkey.resources" ]; then
  cp -R "$BUILD_DIR/.build/release/Donkey_Donkey.resources/." "$RESOURCES_DIR/"
fi

SPARKLE_FRAMEWORK="$(find "$BUILD_DIR/.build" -path "*/release/Sparkle.framework" -type d | head -n 1 || true)"
if [ -z "$SPARKLE_FRAMEWORK" ]; then
  SPARKLE_FRAMEWORK="$(find "$BUILD_DIR/.build" -path "*/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" -type d | head -n 1 || true)"
fi
if [ -n "$SPARKLE_FRAMEWORK" ]; then
  cp -R "$SPARKLE_FRAMEWORK" "$FRAMEWORKS_DIR/"
fi

SPARKLE_PLIST_KEYS=""
if [ -n "$SPARKLE_FEED_URL" ] && [ -n "$SPARKLE_PUBLIC_ED_KEY" ]; then
  SPARKLE_PLIST_KEYS="  <key>SUEnableInstallerLauncherService</key>
  <true/>
  <key>SUEnableDownloaderService</key>
  <true/>
  <key>SUFeedURL</key>
  <string>$SPARKLE_FEED_URL</string>
  <key>SUPublicEDKey</key>
  <string>$SPARKLE_PUBLIC_ED_KEY</string>"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Donkey</string>
  <key>CFBundleIdentifier</key>
  <string>ai.donkey.Donkey</string>
  <key>CFBundleName</key>
  <string>Donkey</string>
  <key>CFBundleDisplayName</key>
  <string>Donkey</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Donkey uses the microphone for local voice commands.</string>
  <key>NSScreenCaptureUsageDescription</key>
  <string>Donkey captures bounded screenshots so local runtimes can understand app UI.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Donkey uses local app automation only for user-requested actions.</string>
$SPARKLE_PLIST_KEYS
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

rm -rf "$DMG_ROOT" "$DMG_PATH"
mkdir -p "$DMG_ROOT"
cp -R "$APP_DIR" "$DMG_ROOT/Donkey.app"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create \
  -volname "Donkey" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null
rm -rf "$DMG_ROOT"

echo "Packaged $APP_DIR"
echo "Created drag-to-Applications disk image: $DMG_PATH"
echo "Open it with: open \"$APP_DIR\""
echo "Test the install flow with: open \"$DMG_PATH\""
echo "For Sparkle updates, package with DONKEY_SPARKLE_FEED_URL and DONKEY_SPARKLE_PUBLIC_ED_KEY."
