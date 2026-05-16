# Real-Time Run Loop And AI Harness Master Plan

This is the active task queue again. A past archive commit closed this roadmap too early: the repo has a useful dry-run/local-navigation scaffold and slow-planner sidecar pieces, but the critical features are not complete yet.

Primary plans:

- `plans/20-off-the-shelf-run-loop.md`
- `plans/19-ai-harness.md`

Supporting plans:

- `plans/01-latency-budget.md`
- `plans/02-capture-and-perception.md`
- `plans/03-fast-controller.md`
- `plans/04-slow-planner.md`
- `plans/05-action-engine.md`
- `plans/06-benchmarking.md`

Supported behavior and engineering guidance belong in `docs/guides/`. This file tracks what is still needed before those active plans can move to `plans/done/`.

## Plan Management Note

Keep this queue grounded in code reality. Move a plan to `plans/done/` only after the relevant behavior is implemented, documented, and verified. If a slice is only scaffolding, dry-run, or provider-specific, call that out here instead of treating it as completion.

## Milestone Goal

Build the first product-shaped loop where Donkey can run a local navigation session with bounded reflex behavior and an optional slow AI sidecar:

```text
local desktop/window/browser context
  -> focused capture / Accessibility / browser-tab metadata
  -> local perception or cheap metadata/template signal
  -> compact world state
  -> deterministic navigation controller
  -> dry-run action trace first, guarded live action later
  -> latency report and replayable trace

slow AI harness
  -> compact snapshot
  -> model router
  -> structured planner hint
  -> validated hint bus
  -> scoped memory proposal
```

The hot path must continue to work with the AI harness disabled.

## Supported Boundary

- Runtime shell: minimal run coordination, ordered events, bounded context assembly, local run artifacts, manual target context capture, in-memory reflex trace retention, and stage-split latency reports are supported.
- Reflex hot path: typed frame/world-state/action contracts, deterministic dry-run loop, bounded target-window frame source, cheap metadata perception, swappable world-state projection, deterministic controller, loop-integrated metadata-only local-navigation dry-run action selection, optional caller-supplied browser-tab metadata, and dry-run action projection are supported. This is not yet fast local navigation using local vision/model inference.
- Safety boundary: action-engine command contracts, permission/focus/rate/hold/release guardrails, guarded live-action smoke with an injected backend, and replayable command traces are supported before any default OS input backend exists.
- Slow AI boundary: structured planner hints, validation/expiry/latest-valid selection, loop-adjacent slow-planner trigger/snapshot sidecar, model registry/router, an OpenAI Responses structured-output adapter, source-linked memory, and replay/eval scaffolding are supported as optional sidecar pieces. This is not yet a complete slow loop using both local and online LLM providers.
- Source of truth: detailed supported behavior lives in `docs/guides/minimal-run-coordinator.md`; active unfinished work lives in this plan and its primary/supporting plans.

## Non-Negotiable Rules

- No remote model call, chat LLM call, or general VLM call may be required for a reflex tick.
- The reflex path uses latest-frame-wins queues; stale frames are dropped and counted.
- The controller consumes typed world state, not raw screenshots.
- The action engine owns OS input; controller policies emit semantic commands only.
- Input starts in dry-run mode. Live input requires policy allowance, focus guard success, and emergency release support.
- Planner output is a validated, expiring hint. It is never direct input.
- Latency claims require monotonic timestamps and a report.
- Full-resolution snapshots, screenshots for AI, and memory writes stay outside the reflex loop.

## Current Reality From Commit Review

Recent commits completed these pieces:

- `9b160f8` and `201e76c`: metadata-only local-navigation dry-run, local-navigation controller contracts, memory/replay scaffolding.
- `0e21088`: OpenAI Responses adapter, planner hint contracts, model registry/router scaffolding.
- `9bebfbb`: slow-planner sidecar trigger/snapshot/hint bus and guarded live-action smoke boundary.
- `d6e48c9`: archived plans, which was premature for this milestone.

The code does not yet include local detector/OCR/segmentation/model inference adapters, continuous local-model navigation, a default OS input backend, a local LLM provider, or a provider-backed slow planner loop that can choose between local and online models.

## What Should Be Done Next

1. Implement fast local navigation with local perception/model evidence, not only window/browser metadata.
2. Implement a slow planner loop that can call both an online provider and a local provider behind the same validated hint boundary.
3. Add benchmark/reporting evidence that local perception, controller, action projection, and input stages meet the target p95 budgets for a concrete target.
4. Keep the current dry-run/guarded-live safety boundary: local or online LLM output can only become validated hints, never direct input.

## Completion Gates

Do not move the primary/supporting plans back to `plans/done/` until:

- Fast local navigation runs from local model/perception output for at least one concrete target, with no remote model dependency in the reflex trace.
- The slow loop can generate validated planner hints through an online LLM provider and a local LLM provider, with strict timeout/failure behavior.
- The hot loop continues to run when the slow AI harness is disabled or failing.
- p50/p95/p99 reports cover capture, preprocessing, local model inference/perception, state update, controller, action projection, and input.
- Action traces can explain state, model/perception evidence, selected rule, validated hint influence, and guardrail decisions.
- The relevant guide in `docs/guides/` documents the supported behavior and boundaries.
