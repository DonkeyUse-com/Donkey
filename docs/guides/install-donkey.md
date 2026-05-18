# Install Donkey Locally

Donkey can be packaged into a local macOS app bundle and drag-to-Applications disk image for manual testing or site distribution.

From the repo root:

```bash
./scripts/package-donkey-app.sh
```

The script builds the release executable, creates `dist/Donkey.app`, copies bundled resources, applies an ad-hoc signature when `codesign` is available, and creates `dist/Donkey.dmg`.

The app bundle version defaults to `0.1.0` build `1`. Override it for local release testing:

```bash
DONKEY_APP_VERSION="0.1.1" DONKEY_APP_BUILD="2" ./scripts/package-donkey-app.sh
```

For distribution through the site, publish the disk image:

```text
dist/Donkey.dmg
```

Opening the disk image mounts a `Donkey` volume with `Donkey.app` and an `Applications` shortcut, matching the standard Codex-style macOS install flow. The user installs Donkey by dragging the app onto the shortcut, which copies it into `/Applications`.

To launch the packaged app:

```bash
open dist/Donkey.app
```

To test the installer flow:

```bash
open dist/Donkey.dmg
```

## Sparkle Updates

Donkey uses Sparkle for app updates. Do not add a Donkey-specific update installer or custom replacement flow; Sparkle owns appcast parsing, update validation, download, install, relaunch, and user-facing update UI.

Configure Sparkle when packaging:

```bash
DONKEY_APP_VERSION="0.1.1" \
DONKEY_APP_BUILD="2" \
DONKEY_SPARKLE_FEED_URL="https://example.com/donkey/appcast.xml" \
DONKEY_SPARKLE_PUBLIC_ED_KEY="..." \
./scripts/package-donkey-app.sh
```

For local update testing, use Sparkle's standard local appcast workflow:

1. Package the older app and install it in `/Applications`.
2. Package the newer app with a higher `DONKEY_APP_VERSION` / `DONKEY_APP_BUILD`.
3. Use Sparkle's `generate_appcast` tooling over the folder containing the newer update archive.
4. Package or launch the older app with `DONKEY_SPARKLE_FEED_URL` pointing to the local `file://` appcast and `DONKEY_SPARKLE_PUBLIC_ED_KEY` set to the matching public EdDSA key.

Example feed URL shape:

```bash
DONKEY_SPARKLE_FEED_URL="file:///Users/me/donkey-updates/appcast.xml"
```

When Sparkle finds a valid signed update, the expanded notch task panel shows an update button in its header. Clicking it invokes Sparkle's standard update UI.

The package script also creates Donkey-compatible sidecar runner packages under `dist/LocalRuntimePackages` and embeds them into:

```text
dist/Donkey.app/Contents/Resources/LocalRuntimePackages/
```

Parakeet and YOLO runner packages include manifest-tracked Python requirements. On setup, the sidecar creates a managed virtual environment under Application Support and installs those dependencies there. A package-local `wheelhouse/` directory can be added beside `requirements.txt` when the release build needs offline dependency installation for the supported macOS target.

On first launch, Donkey shows one setup button for local runtimes. Setup installs the bundled sidecar packages first, verifies their manifests/checksums, registers them in Application Support, asks them to prepare model weights, and health-checks them. The bundled packages do not include model weights; they contain protocol-speaking runner entrypoints for the local command parser, Parakeet voice transcription, YOLO screenshot segmentation, and UI understanding. If setup fails, clicking the same button retries failed or not-yet-attempted runtimes while keeping completed installs.

Each bundled sidecar supports setup-time model weight preparation. During setup, Donkey calls the sidecar with `prepareModelWeights`; the sidecar downloads or warms the configured model cache and reports cached/downloaded status before health check. The local command-parser LLM is setup-managed too: Donkey packages a `local-llm` sidecar that pulls `qwen3:8b` through Ollama by default, then submitted commands are parsed through `DONKEY_LOCAL_LLM_RUNNER` instead of a direct in-app Ollama request. The Parakeet runner can fetch the Hugging Face snapshot when `huggingface_hub` is available and transcribes through NVIDIA NeMo when the local Python backend is installed.

Configure model-weight URLs when packaging:

```bash
DONKEY_PARAKEET_MODEL_URL="https://..." \
DONKEY_PARAKEET_MODEL_SHA256="..." \
DONKEY_YOLO_MODEL_URL="https://..." \
DONKEY_YOLO_MODEL_SHA256="..." \
DONKEY_UI_UNDERSTANDER_MODEL_URL="https://..." \
DONKEY_UI_UNDERSTANDER_MODEL_SHA256="..." \
DONKEY_LOCAL_LLM_MODEL_ID="qwen3:8b" \
./scripts/package-donkey-app.sh
```

If a model URL/backend is missing for a file-backed sidecar, Ollama is unavailable for the local LLM sidecar, or Parakeet's local Python backend is missing, setup or runtime calls fail clearly with a retryable needs-attention state instead of pretending the runtime is usable.
