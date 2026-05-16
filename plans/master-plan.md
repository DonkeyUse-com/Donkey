# Real-Time Run Loop And AI Harness Master Plan

This file is the active task queue for closing out the off-the-shelf real-time run loop and slow-path AI harness milestones.

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

Supported behavior and engineering guidance belong in `docs/guides/`. This master plan should stay small: keep only critical current-boundary context and the active queue.

## Plan Management Note

As work progresses, move only still-actionable items out of the supporting plans and into this master plan so there is one active queue. Do not grow a historical completed-task log here. When a slice becomes supported, update the supported-boundary summary below and the relevant guide in `docs/guides/`; use search across `docs/` and `plans/` for older implementation history.

When a supporting plan has no remaining active work, either move it to `plans/done/` if its acceptance criteria are supported, or leave it active only for clearly named future work that still remains.

## Milestone Goal

Build the first product-shaped loop where Donkey can run a target-window session with local, bounded reflex behavior and an optional slow AI sidecar:

```text
target window capture
  -> crop / normalize
  -> local perception or cheap template signal
  -> compact world state
  -> deterministic controller
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

- Runtime shell: minimal run coordination, ordered events, bounded context assembly, local run artifacts, manual target context capture, in-memory reflex trace retention, and latency reports are supported.
- Reflex hot path: typed frame/world-state/action contracts, deterministic dry-run loop, bounded target-window frame source, cheap metadata perception, deterministic controller, and dry-run action projection are supported. Live OS input is not supported.
- Safety boundary: action-engine command contracts, permission/focus/rate/hold/release guardrails, and replayable command traces are supported before live input.
- Slow AI boundary: structured planner hints, validation/expiry/latest-valid selection, model registry/router, and an OpenAI Responses structured-output adapter are supported as optional sidecar pieces. The hot loop still runs without AI output.
- Source of truth: detailed supported behavior lives in `docs/guides/minimal-run-coordinator.md`; historical implementation details should be found with search in `docs/`, `plans/`, and git history, not duplicated here.

## Non-Negotiable Rules

- No remote model call, chat LLM call, or general VLM call may be required for a reflex tick.
- The reflex path uses latest-frame-wins queues; stale frames are dropped and counted.
- The controller consumes typed world state, not raw screenshots.
- The action engine owns OS input; controller policies emit semantic commands only.
- Input starts in dry-run mode. Live input requires policy allowance, focus guard success, and emergency release support.
- Planner output is a validated, expiring hint. It is never direct input.
- Latency claims require monotonic timestamps and a report.
- Full-resolution snapshots, screenshots for AI, and memory writes stay outside the reflex loop.

## Active Queue

1. Add short-term and target memory.
   - Build short-term run memory in process for current goal, active hints, recent states, failures, user instructions, and safety stops.
   - Add target memory as scoped, source-linked JSONL records.
   - Require TTL or deliberate durable target scope.
   - Add deterministic approval for model-proposed memory writes.
   - Make memory records inspectable and deleteable by target, run, and user scope.

2. Add replay/eval for model and prompt changes.
   - Evaluate planner hints against recorded traces before promotion.
   - Track schema validity, hint acceptance, memory write acceptance, latency, cost, fallback count, and recovery success.
   - Add a model update checklist that records `last_verified_at`, docs URLs, eval suite id, and rollback model id.

3. Integrate slow planner beside the dry-run loop.
   - Trigger planner calls on scene change, low confidence, repeated failure, goal completion, or user instruction.
   - Build compact snapshots from world state, trace summaries, optional screenshots, and memory.
   - Publish only validated hints to the controller.
   - Prove planner latency does not move p95 reflex latency.

4. Enable guarded live-action smoke only after dry-run closeout.
   - Pick one target and one behavior.
   - Run end-to-end dry-run with input disabled and latency report passing.
   - Enable live input only with explicit policy allowance and focus guard.
   - Verify abort and timeout release held input.
   - Record trace evidence for every action.

5. Close out the primary plans.
   - Update supported behavior guides in `docs/guides/`.
   - Move `plans/20-off-the-shelf-run-loop.md` to `plans/done/` when the reflex loop acceptance criteria are supported.
   - Move `plans/19-ai-harness.md` to `plans/done/` when the AI harness acceptance criteria are supported.
   - Move supporting plans to `plans/done/` only if their acceptance criteria are fully satisfied; otherwise update them to describe the remaining future work.
   - Move this master plan to `plans/done/` after both primary plans are closed out.

## What Should Be Done Next

Start with active task 1: add short-term and target memory.

This is the right next slice because the current boundary has a dry-run reflex path, guardrails, latency reporting, validated planner hints, model routing, and the first slow-path adapter. It still needs scoped short-term and target memory before planner hints and future memory writes can be source-linked, inspectable, and deleteable.

## Closeout Criteria

This master plan is complete when:

- The off-the-shelf run loop can run a selected target in dry-run mode end to end.
- A selected first behavior can be exercised with guarded live input after dry-run success.
- Capture, perception, controller, action, and input stages are measured with monotonic timestamps.
- p50 and p95 reflex latency are reported for the first supported target.
- The hot loop still works with the AI harness disabled.
- Planner hints are structured, validated, expiring, trace-linked, and optional.
- Memory writes are source-linked, scoped, inspectable, deleteable, and deterministically approved.
- Model routing uses registry roles instead of scattered literal model ids.
- Replay/eval exists for controller traces and model/prompt changes.
- Supported behavior is documented in `docs/guides/`.
- `plans/19-ai-harness.md` and `plans/20-off-the-shelf-run-loop.md` are moved to `plans/done/`.
