#!/usr/bin/env python3
"""Install local runtime packages for `scripts/run-donkey-dev.sh`."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


RUNTIME_ENV_NAMES = {
    "local-llm": "DONKEY_LOCAL_LLM_RUNTIME_MANIFEST_URL",
    "parakeet-transcriber": "DONKEY_PARAKEET_RUNTIME_MANIFEST_URL",
    "ui-understander": "DONKEY_UI_UNDERSTANDER_RUNTIME_MANIFEST_URL",
    "yolo-segmenter": "DONKEY_YOLO_RUNTIME_MANIFEST_URL",
}

RUNTIME_EXECUTABLE_ENV_NAMES = {
    "local-llm": "DONKEY_LOCAL_LLM_RUNNER",
    "parakeet-transcriber": "DONKEY_PARAKEET_TRANSCRIBER",
    "ui-understander": "DONKEY_UI_UNDERSTANDER",
    "yolo-segmenter": "DONKEY_YOLO_SEGMENTER",
}

DEFAULT_BASE_DIR = (
    Path.home()
    / "Library"
    / "Application Support"
    / "Donkey"
    / "LocalModelRuntimes"
)


def main() -> int:
    manifest_urls = configured_manifest_urls()
    if not manifest_urls:
        print("No local runtime manifest URLs are configured; skipping dev runtime setup.")
        return 0

    base_dir = Path(os.environ.get("DONKEY_DEV_RUNTIME_BASE_DIR", DEFAULT_BASE_DIR)).expanduser()
    registry = load_registry(base_dir)
    changed = False
    prepared_any = False

    for runtime_id, manifest_url in sorted(manifest_urls.items()):
        manifest = read_json_url(manifest_url)
        actual_runtime_id = str(manifest.get("runtimeID") or runtime_id)
        if actual_runtime_id != runtime_id:
            print(f"warning: manifest runtime mismatch for {runtime_id}: {actual_runtime_id}", file=sys.stderr)
            continue

        installation = registry.get("installations", {}).get(runtime_id)
        if installation_is_current(base_dir, installation, manifest):
            print(f"runtime {runtime_id}: already installed")
            continue

        installation = install_runtime(base_dir, manifest)
        registry.setdefault("installations", {})[runtime_id] = installation
        save_registry(base_dir, registry)
        changed = True
        print(f"runtime {runtime_id}: installed {installation['runtimeVersion']}")

        if os.environ.get("DONKEY_DEV_RUNTIME_PREPARE", "1") != "0":
            prepared_any = True
            prepare_and_check(base_dir, installation, manifest)

    if not changed:
        print("dev local runtime setup: nothing missing")
    elif not prepared_any:
        print("dev local runtime setup: installed missing packages; model preparation skipped")
    else:
        print("dev local runtime setup: finished missing-runtime pass")
    return 0


def configured_manifest_urls() -> dict[str, str]:
    urls: dict[str, str] = {}
    combined = os.environ.get("DONKEY_RUNTIME_PACKAGE_MANIFEST_URLS", "")
    for pair in combined.split(","):
        if not pair or "=" not in pair:
            continue
        runtime_id, value = pair.split("=", 1)
        if runtime_id and value:
            urls[runtime_id] = value

    for runtime_id, env_name in RUNTIME_ENV_NAMES.items():
        value = os.environ.get(env_name, "")
        if value:
            urls[runtime_id] = value
    return urls


def read_json_url(url: str) -> dict[str, Any]:
    with urllib.request.urlopen(url, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def load_registry(base_dir: Path) -> dict[str, Any]:
    registry_path = registry_file(base_dir)
    if not registry_path.exists():
        return {"installations": {}}
    try:
        return json.loads(registry_path.read_text())
    except json.JSONDecodeError:
        return {"installations": {}}


def save_registry(base_dir: Path, registry: dict[str, Any]) -> None:
    base_dir.mkdir(parents=True, exist_ok=True)
    registry_path = registry_file(base_dir)
    fd, tmp_name = tempfile.mkstemp(prefix=".runtime-installations.", suffix=".json", dir=base_dir)
    try:
        with os.fdopen(fd, "w") as output:
            json.dump(registry, output, indent=2, sort_keys=True)
            output.write("\n")
        Path(tmp_name).replace(registry_path)
    finally:
        Path(tmp_name).unlink(missing_ok=True)


def registry_file(base_dir: Path) -> Path:
    return base_dir / "runtime-installations.json"


def installation_is_current(
    base_dir: Path,
    installation: dict[str, Any] | None,
    manifest: dict[str, Any],
) -> bool:
    if os.environ.get("DONKEY_DEV_RUNTIME_FORCE_SETUP", "0") == "1":
        return False
    if not isinstance(installation, dict):
        return False
    executable_path = Path(str(installation.get("executablePath") or ""))
    if not executable_path.is_file() or not os.access(executable_path, os.X_OK):
        return False
    if str(installation.get("runtimeVersion") or "") != str(manifest.get("runtimeVersion") or ""):
        return False
    if str(installation.get("modelID") or "") != str(manifest.get("modelID") or ""):
        return False
    downloaded_dir = Path(str(installation.get("downloadedDirectoryPath") or ""))
    if not is_relative_to(downloaded_dir, base_dir) or not downloaded_dir.exists():
        return False
    manifest_metadata = manifest.get("metadata") if isinstance(manifest.get("metadata"), dict) else {}
    install_metadata = installation.get("metadata") if isinstance(installation.get("metadata"), dict) else {}
    for key in ["modelWeights.downloadURL", "modelWeights.sha256", "modelWeights.filename", "runtime.package"]:
        if str(install_metadata.get(key) or "") != str(manifest_metadata.get(key) or ""):
            return False
    for item in manifest.get("files", []):
        if not isinstance(item, dict):
            return False
        relative_path = str(item.get("relativePath") or "")
        expected_sha = str(item.get("sha256") or "").lower()
        if not relative_path or not expected_sha:
            return False
        installed_file = safe_join(downloaded_dir, relative_path)
        if not installed_file.exists():
            return False
        if hashlib.sha256(installed_file.read_bytes()).hexdigest() != expected_sha:
            return False
        if bool(item.get("isExecutable")) and not os.access(installed_file, os.X_OK):
            return False
    return True


def install_runtime(base_dir: Path, manifest: dict[str, Any]) -> dict[str, Any]:
    runtime_id = str(manifest["runtimeID"])
    runtime_version = str(manifest["runtimeVersion"])
    managed_dir = base_dir / "Packages" / runtime_id / runtime_version
    if is_relative_to(managed_dir, base_dir) and managed_dir.exists():
        shutil.rmtree(managed_dir)
    managed_dir.mkdir(parents=True, exist_ok=True)

    for item in manifest.get("files", []):
        relative_path = str(item["relativePath"])
        destination = safe_join(managed_dir, relative_path)
        destination.parent.mkdir(parents=True, exist_ok=True)
        data = read_url_bytes(str(item["downloadURL"]))
        actual_sha = hashlib.sha256(data).hexdigest()
        expected_sha = str(item["sha256"]).lower()
        if actual_sha != expected_sha:
            raise RuntimeError(f"{runtime_id} {relative_path} hash mismatch: {actual_sha} != {expected_sha}")
        destination.write_bytes(data)
        if bool(item.get("isExecutable")):
            destination.chmod(0o755)

    executable_path = safe_join(managed_dir, str(manifest["executableRelativePath"]))
    if not executable_path.is_file() or not os.access(executable_path, os.X_OK):
        raise RuntimeError(f"installed executable missing or not executable: {executable_path}")

    metadata = {
        "installedBy": "donkey-dev-runtime-setup",
        "manifest.platform": str(manifest.get("platform") or ""),
        "manifest.architecture": str(manifest.get("architecture") or ""),
        "manifest.minimumDonkeyVersion": str(manifest.get("minimumDonkeyVersion") or ""),
        "manifest.signingKeyID": str(manifest.get("signingKeyID") or ""),
        "manifest.signaturePresent": str(manifest.get("signature") is not None).lower(),
    }
    manifest_metadata = manifest.get("metadata")
    if isinstance(manifest_metadata, dict):
        metadata.update({str(key): str(value) for key, value in manifest_metadata.items()})

    return {
        "runtimeID": runtime_id,
        "executablePath": str(executable_path),
        "downloadedDirectoryPath": str(managed_dir),
        "installedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "runtimeVersion": runtime_version,
        "modelID": str(manifest.get("modelID") or ""),
        "sidecarProtocolVersion": str(manifest.get("sidecarProtocolVersion") or "v1"),
        "metadata": metadata,
    }


def read_url_bytes(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=60) as response:
        return response.read()


def safe_join(root: Path, relative_path: str) -> Path:
    candidate = root
    for component in Path(relative_path).parts:
        if component in {"", ".", ".."}:
            raise RuntimeError(f"unsafe runtime package path: {relative_path}")
        candidate = candidate / component
    return candidate


def prepare_and_check(base_dir: Path, installation: dict[str, Any], manifest: dict[str, Any]) -> None:
    runtime_id = str(installation["runtimeID"])
    cache_dir = model_cache_dir(base_dir, installation)
    cache_dir.mkdir(parents=True, exist_ok=True)
    request = {
        "operation": "prepareModelWeights",
        "protocolVersion": str(installation.get("sidecarProtocolVersion") or "v1"),
        "runtimeID": runtime_id,
        "runtimeVersion": str(installation.get("runtimeVersion") or ""),
        "modelID": str(installation.get("modelID") or manifest.get("modelID") or ""),
        "cacheDirectory": str(cache_dir),
        "metadata": metadata_for_sidecar(installation, manifest),
    }
    print(f"runtime {runtime_id}: preparing model weights and backend...", flush=True)
    prepare = run_sidecar(installation, request, timeout_seconds=dev_timeout("DONKEY_DEV_RUNTIME_PREPARE_TIMEOUT_SECONDS", 600))
    print_sidecar_status(runtime_id, "prepare", prepare)

    health_request = dict(request)
    health_request["operation"] = "healthCheck"
    print(f"runtime {runtime_id}: checking health...", flush=True)
    health = run_sidecar(installation, health_request, timeout_seconds=dev_timeout("DONKEY_DEV_RUNTIME_HEALTH_TIMEOUT_SECONDS", 15))
    print_sidecar_status(runtime_id, "health", health)


def metadata_for_sidecar(installation: dict[str, Any], manifest: dict[str, Any]) -> dict[str, str]:
    values: dict[str, str] = {}
    spec_metadata = manifest.get("metadata")
    if isinstance(spec_metadata, dict):
        values.update({str(key): str(value) for key, value in spec_metadata.items()})
    install_metadata = installation.get("metadata")
    if isinstance(install_metadata, dict):
        values.update({str(key): str(value) for key, value in install_metadata.items()})
    return values


def run_sidecar(installation: dict[str, Any], request: dict[str, Any], timeout_seconds: int) -> dict[str, Any]:
    runtime_id = str(installation["runtimeID"])
    executable_path = str(installation["executablePath"])
    environment = os.environ.copy()
    env_name = RUNTIME_EXECUTABLE_ENV_NAMES.get(runtime_id)
    if env_name:
        environment[env_name] = executable_path
    try:
        completed = subprocess.run(
            [executable_path],
            input=json.dumps(request),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=environment,
            timeout=timeout_seconds,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return {"status": "timeout", "metadata": {"reason": "timeout"}}

    try:
        payload = json.loads(completed.stdout or "{}")
    except json.JSONDecodeError:
        payload = {"status": "invalidOutput", "metadata": {"stdout": completed.stdout[-400:]}}
    if completed.returncode != 0:
        payload.setdefault("metadata", {})["exitCode"] = str(completed.returncode)
    if completed.stderr:
        payload.setdefault("metadata", {})["stderr"] = completed.stderr[-400:]
    return payload


def print_sidecar_status(runtime_id: str, phase: str, payload: dict[str, Any]) -> None:
    status = str(payload.get("status") or "unknown")
    metadata = payload.get("metadata") if isinstance(payload.get("metadata"), dict) else {}
    reason = metadata.get("reason") or metadata.get("modelWeights.status") or "-"
    output = f"runtime {runtime_id}: {phase} {status} ({reason})"
    if status == "ok":
        print(output)
    else:
        print(f"warning: {output}", file=sys.stderr)


def model_cache_dir(base_dir: Path, installation: dict[str, Any]) -> Path:
    model_id = str(installation.get("modelID") or installation["runtimeID"]).replace("/", "-").replace(":", "-")
    return base_dir / "ModelWeights" / str(installation["runtimeID"]) / model_id


def dev_timeout(name: str, default_value: int) -> int:
    try:
        return max(1, int(os.environ.get(name, str(default_value))))
    except ValueError:
        return default_value


def is_relative_to(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


if __name__ == "__main__":
    raise SystemExit(main())
