#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${DONKEY_RUNTIME_WHEELHOUSE_ROOT:-$ROOT_DIR/dist/LocalRuntimeWheelhouses}"
PYTHON="${DONKEY_RUNTIME_PYTHON:-python3}"
PIP_DOWNLOAD_ARGS="${DONKEY_PIP_DOWNLOAD_ARGS:-}"

mkdir -p "$OUTPUT_DIR"

download_wheelhouse() {
  local runtime_id="$1"
  local requirements="$2"
  local runtime_dir="$OUTPUT_DIR/$runtime_id"
  local requirements_file
  requirements_file="$(mktemp)"

  rm -rf "$runtime_dir"
  mkdir -p "$runtime_dir"
  printf '%s\n' "$requirements" > "$requirements_file"

  # shellcheck disable=SC2086
  "$PYTHON" -m pip download \
    --only-binary=:all: \
    --dest "$runtime_dir" \
    -r "$requirements_file" \
    $PIP_DOWNLOAD_ARGS

  rm -f "$requirements_file"
  find "$runtime_dir" -maxdepth 1 -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 shasum -a 256 > "$runtime_dir/SHA256SUMS"
}

parakeet_requirements=$'huggingface_hub>=0.25,<1'
if [ -n "${DONKEY_PARAKEET_EXTRA_REQUIREMENTS:-}" ]; then
  parakeet_requirements="$parakeet_requirements
$DONKEY_PARAKEET_EXTRA_REQUIREMENTS"
fi

download_wheelhouse "parakeet-transcriber" "$parakeet_requirements"
download_wheelhouse "yolo-segmenter" $'ultralytics>=8.3,<9\nopencv-python-headless>=4.10,<5'

echo "Built local runtime wheelhouses in $OUTPUT_DIR"
echo "Package them with: DONKEY_RUNTIME_WHEELHOUSE_ROOT=\"$OUTPUT_DIR\" ./scripts/package-donkey-app.sh"
