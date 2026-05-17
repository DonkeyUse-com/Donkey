#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/Donkey.app"
RUNTIME_PACKAGE_DIR="$ROOT_DIR/dist/LocalRuntimePackages"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BUILD_DIR="$ROOT_DIR/apps/Donkey"
EXECUTABLE="$BUILD_DIR/.build/release/Donkey"
CACHE_DIR="$BUILD_DIR/.build/package-cache"

mkdir -p "$CACHE_DIR/clang" "$CACHE_DIR/swiftpm" "$CACHE_DIR/home"
export CLANG_MODULE_CACHE_PATH="$CACHE_DIR/clang"
export SWIFTPM_CACHE_PATH="$CACHE_DIR/swiftpm"
export HOME="$CACHE_DIR/home"

cd "$BUILD_DIR"
swift build -c release --product Donkey

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$EXECUTABLE" "$MACOS_DIR/Donkey"

make_runtime_package() {
  local runtime_id="$1"
  local executable_name="$2"
  local model_id="$3"
  local role="$4"
  local package_dir="$RUNTIME_PACKAGE_DIR/$runtime_id"
  local bin_dir="$package_dir/bin"
  local executable_path="$bin_dir/$executable_name"

  mkdir -p "$bin_dir"
  cat > "$executable_path" <<EOF_RUNTIME
#!/usr/bin/env sh
REQUEST="\$(cat)"
if printf '%s' "\$REQUEST" | grep -q '"operation"[[:space:]]*:[[:space:]]*"healthCheck"'; then
  printf '{"status":"ok","runtimeID":"$runtime_id","runtimeVersion":"0.1.0-bootstrap","modelID":"$model_id","protocolVersion":"v1","metadata":{"runtime.package":"bundled-bootstrap","modelWeightsBundled":"false","sidecar.role":"$role"}}'
  exit 0
fi

case "$runtime_id" in
  parakeet-transcriber)
    printf '{"text":"","language":null,"confidence":0,"segments":[],"metadata":{"runtime.package":"bundled-bootstrap","modelWeightsBundled":"false","reason":"modelWeightsNotInstalled"}}'
    ;;
  yolo-segmenter)
    printf '{"masks":[],"preprocessMS":0,"modelInferenceMS":0,"metadata":{"runtime.package":"bundled-bootstrap","modelWeightsBundled":"false","reason":"modelWeightsNotInstalled"}}'
    ;;
  ui-understander)
    printf '{"visibleText":{},"controls":[],"formFields":[],"confidence":0,"metadata":{"runtime.package":"bundled-bootstrap","modelWeightsBundled":"false","reason":"modelWeightsNotInstalled"}}'
    ;;
esac
EOF_RUNTIME
  chmod 755 "$executable_path"

  local sha
  sha="$(shasum -a 256 "$executable_path" | awk '{print $1}')"
  cat > "$package_dir/manifest.json" <<EOF_MANIFEST
{
  "runtimeID" : "$runtime_id",
  "runtimeVersion" : "0.1.0-bootstrap",
  "modelID" : "$model_id",
  "platform" : "macos",
  "architecture" : "$(uname -m | sed 's/aarch64/arm64/;s/x86_64/x86_64/')",
  "sidecarProtocolVersion" : "v1",
  "minimumDonkeyVersion" : "0.1.0",
  "executableRelativePath" : "bin/$executable_name",
  "files" : [
    {
      "relativePath" : "bin/$executable_name",
      "sha256" : "$sha",
      "isExecutable" : true
    }
  ],
  "signature" : "bundled-bootstrap-package",
  "signingKeyID" : "donkey-bootstrap",
  "metadata" : {
    "runtime.package" : "bundled-bootstrap",
    "modelWeightsBundled" : "false",
    "sidecar.role" : "$role"
  }
}
EOF_MANIFEST
}

rm -rf "$RUNTIME_PACKAGE_DIR"
mkdir -p "$RUNTIME_PACKAGE_DIR"
make_runtime_package "parakeet-transcriber" "donkey-parakeet-transcriber" "nvidia/parakeet-tdt-0.6b-v3" "voiceTranscription"
make_runtime_package "yolo-segmenter" "donkey-yolo-segmenter" "ultralytics/yolo26n-seg" "screenshotSegmentation"
make_runtime_package "ui-understander" "donkey-ui-understander" "local-ui-understander" "uiUnderstanding"
cp -R "$RUNTIME_PACKAGE_DIR" "$RESOURCES_DIR/LocalRuntimePackages"

RESOURCE_BUNDLE="$(find "$BUILD_DIR/.build" -path "*/release/Donkey_Donkey.bundle" -type d | head -n 1 || true)"
if [ -n "$RESOURCE_BUNDLE" ]; then
  cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
elif [ -d "$BUILD_DIR/.build/release/Donkey_Donkey.resources" ]; then
  cp -R "$BUILD_DIR/.build/release/Donkey_Donkey.resources/." "$RESOURCES_DIR/"
fi

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
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
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Donkey uses the microphone for local voice commands.</string>
  <key>NSScreenCaptureUsageDescription</key>
  <string>Donkey captures bounded screenshots so local runtimes can understand app UI.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Donkey uses local app automation only for user-requested actions.</string>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

echo "Packaged $APP_DIR"
echo "Open it with: open \"$APP_DIR\""
