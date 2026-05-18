# Install Donkey Locally

Donkey can be packaged into a local macOS app bundle for manual testing.

From the repo root:

```bash
./scripts/package-donkey-app.sh
```

The script builds the release executable, creates `dist/Donkey.app`, copies bundled resources, and applies an ad-hoc signature when `codesign` is available.

To launch the packaged app:

```bash
open dist/Donkey.app
```

The package script also creates Donkey-compatible sidecar runner packages under `dist/LocalRuntimePackages` and embeds them into:

```text
dist/Donkey.app/Contents/Resources/LocalRuntimePackages/
```

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
