# Local Runtime Onboarding Plan

Completed. This plan is historical context for Donkey's first-run local runtime
setup flow.

## Supported Outcome

Donkey now supports a normal post-install runtime setup boundary:

- first-launch setup window with one primary setup button
- app-managed runtime registry under Application Support
- bundled runner packages embedded in `Donkey.app`
- manifest validation for runtime id, platform, architecture, executable path,
  required signature metadata, and SHA-256 file hashes
- package install into managed Application Support directories
- setup-time model preparation before health checks
- sidecar `healthCheck` protocol
- retryable setup that keeps completed installs and resumes failed or missing
  runtimes
- app-registry sidecar resolution when shell environment variables are absent
- developer debug commands for setup instructions, status, and manual runtime
  registration

The supported behavior is documented in:

- `docs/architecture.md`
- `docs/guides/install-donkey.md`
- `docs/guides/minimal-run-coordinator.md`

## Follow-Up Work

Remaining release hardening is tracked by `plans/master-plan.md`, not this
completed plan. That includes offline wheelhouse artifacts, final backend
packaging, cryptographic release-key verification, runtime repair/remove flows,
a settings entry to reopen setup, support export, and the final command-parser
LLM prerequisite decision.
