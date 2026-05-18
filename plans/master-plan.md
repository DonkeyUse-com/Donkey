# Fast Local Navigation Agent Master Plan

This is the active queue for the fast local navigation milestone. Completed
behavior belongs in `docs/guides/` and `docs/architecture.md`; do not keep
completed implementation history here.

## Goal

Donkey should take a short local command, resolve it to app-task knowledge,
navigate the local desktop/app surface, perform guarded local actions, verify the
result, and emit a replayable latency trace.

The benchmark command remains:

```text
show me the weather for SF
```

Weather is only benchmark data. The same generic loop should also support app
tasks such as media playback and review-first document form fill.

## Active Plans

- `plans/20-off-the-shelf-run-loop.md`
- `plans/19-ai-harness.md`
- `plans/01-latency-budget.md`
- `plans/02-capture-and-perception.md`
- `plans/03-fast-controller.md`
- `plans/05-action-engine.md`
- `plans/06-benchmarking.md`
- `plans/22-local-runtime-onboarding.md`

Treat other `plans/` files as background unless this plan names them.

## Current Boundary

The local navigation loop, task catalog, guarded input boundary, sidecar runner
contracts, local runtime setup UI, manifest/checksum installation, model-prep
hooks, latency reporting, memory/redaction/observability scaffolding, and
optional slow-planner hint path are supported and documented.

The milestone is not release-complete because local runtime packaging is still
not self-contained.

## What Remains

1. Ship release-grade local runtime packages:
   - publish offline wheelhouse-backed Parakeet and YOLO bundles for supported
     macOS targets
   - decide whether Parakeet's NVIDIA NeMo backend ships prepared or remains an
     optional backend
   - replace the UI-understanding placeholder with a real local backend
   - replace the Ollama-backed command-parser LLM with a self-contained runner,
     or explicitly keep Ollama as a documented prerequisite

2. Harden runtime trust and lifecycle:
   - verify runtime manifests with release-key cryptographic signatures, not
     signature metadata alone
   - add behind-the-scenes repair/remove flows for broken runtime installs
   - keep the first-run setup button retryable without exposing per-runtime user
     customization

3. Clean up command parsing policy:
   - decide whether submitted commands may keep deterministic built-in fallback
     when the local LLM sidecar is unavailable
   - make code, docs, and tests agree on that policy

4. Prove the benchmark:
   - run "show me the weather for SF" through a verified Weather result with no
     remote dependency in the execution trace
   - compare latency against a documented manual baseline on the same machine

## Invariants

- No remote model call, chat LLM call, or general VLM call may be required for a
  reflex tick.
- The reflex path uses latest-frame-wins queues, typed world state, semantic
  controller actions, and action-engine-owned OS input.
- Live input requires policy allowance, focus guard success, rate/hold/release
  guardrails, and replayable traces.
- Slow AI output can become validated intent, task definitions, app-knowledge
  updates, observation summaries, transcripts, memory proposals, or planner
  hints. It must not become direct input.
- Latency claims require monotonic timestamps and p50/p95/p99 reports.

## Completion Gates

Do not move the active plans to `plans/done/` until:

- Weather lookup completes end to end locally and verifies the Weather result.
- Dry-run and guarded-live traces explain parsing, launch/focus, observation,
  selected rule, input/backend calls, verification, and guardrails.
- Voice commands, when enabled, transcribe locally before command parsing.
- The hot loop keeps working when the slow AI harness is disabled or failing.
- Runtime packaging, trust verification, and setup repair are release-grade.
- Guides document the supported behavior and boundaries.
