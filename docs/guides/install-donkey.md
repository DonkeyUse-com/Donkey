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

The package script also creates Donkey-compatible bootstrap sidecar runtime packages under `dist/LocalRuntimePackages` and embeds them into:

```text
dist/Donkey.app/Contents/Resources/LocalRuntimePackages/
```

On first launch, Donkey shows one setup button for local runtimes. Setup installs the bundled sidecar packages first, verifies their manifests/checksums, registers them in Application Support, and health-checks them. The bundled packages do not include model weights; they are the installation surface for the sidecar runners. If setup fails, clicking the same button retries failed or not-yet-attempted runtimes while keeping completed installs.
