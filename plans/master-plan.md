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

Supported behavior and engineering guidance belong in `docs/guides/`. This master plan should shrink as slices become supported.

## Plan Management Note

As work progresses, move actionable items out of the supporting plans and into this master plan so there is one active queue. When a supporting plan has no remaining active work, either move it to `plans/done/` if its acceptance criteria are supported, or leave it active only for clearly named future work that still remains.

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

## Current Supported Baseline

- Minimal run coordination exists: session queueing, lifecycle events, policy checks, context compaction, abort/timeout input-release flags, and ordered event publication.
- Local run artifact storage exists for `events.jsonl`, `summary.json`, screenshots, and Accessibility artifacts.
- Manual target context capture exists for selected macOS windows with screenshot and bounded read-only Accessibility artifacts.
- The first reflex trace contract exists: monotonic stage timestamps, latency breakdown, bounded in-memory trace retention, and matching coordinator `reflex` events.
- Shared hot-loop contracts exist for frames, crops, explicit coordinate spaces, perception signals, compact world state, controller actions, action results, stale-signal marking, and trace-linked IDs.
- A deterministic dry-run reflex loop skeleton exists for synthetic or recorded frame batches with latest-frame-wins queue depth 1, dropped-frame counting, dry-run action projection, and coordinator-published reflex traces.
- Bounded target-window frame capture exists for the dry-run hot-loop boundary with selected-window safety checks, optional crop metadata, monotonic capture/copy timing, and no PNG/JPEG artifact encoding.

## Non-Negotiable Rules

- No remote model call, chat LLM call, or general VLM call may be required for a reflex tick.
- The reflex path uses latest-frame-wins queues; stale frames are dropped and counted.
- The controller consumes typed world state, not raw screenshots.
- The action engine owns OS input; controller policies emit semantic commands only.
- Input starts in dry-run mode. Live input requires policy allowance, focus guard success, and emergency release support.
- Planner output is a validated, expiring hint. It is never direct input.
- Latency claims require monotonic timestamps and a report.
- Full-resolution snapshots, screenshots for AI, and memory writes stay outside the reflex loop.

## Completed Tasks

- [x] Complete manual target context capture milestone.
- [x] Add the first reflex trace contract and bounded in-memory trace retention.
- [x] Publish reflex trace records through `RunCoordinator` as sampled `reflex` events.
- [x] Define shared hot-loop contracts for typed frame, crop, world-state, perception-signal, controller-action, action-result, and coordinate conversion.
- [x] Add deterministic dry-run reflex loop skeleton for synthetic or recorded frames only.
- [x] Add bounded target-window capture as a dry-run frame source without screenshot artifact writes.

## Remaining Tasks

4. Add the first cheap perception adapter.
   - Start with deterministic template, color, edge, OCR-crop stub, or synthetic detector signal before adding heavier models.
   - Convert perception output into compact world state.
   - Include signal confidence and age.
   - Keep detector tensors, masks, and raw pixels behind perception boundaries.
   - Add replay tests from recorded or fixture frames.

5. Add deterministic controller and dry-run action projection.
   - Define policy selection and one inspectable rule/state-machine policy for the first supported behavior.
   - Emit semantic action commands with state id, action id, policy name, confidence, and rationale metadata.
   - Add confidence-aware fallback behavior.
   - Record every chosen action in traces.
   - Prove controller p95 decision time under 20ms in replay.

6. Add action-engine guardrails before live input.
   - Define command interface for tap, swipe, key, mouse, controller, and `release_all`.
   - Add focus guard, permission policy check, held-input release, rate limits, and maximum hold durations.
   - Keep live input disabled by default until dry-run traces and guard behavior pass.
   - Add replayable command traces.

7. Add latency reports and replay benchmark mode.
   - Produce a CLI latency report from reflex traces.
   - Report p50/p95/p99, capture FPS, perception FPS, controller tick rate, dropped frames, stale actions, and worst traces.
   - Add capture-only, controller-only, and end-to-end dry-run benchmark modes.
   - Add baseline files per target and machine class when a real target is selected.

8. Add slow-path planner hint contracts.
   - Define structured planner hint schema with goal, policy, priorities, regions of interest, avoid actions, confidence, expiry, and source ids.
   - Validate unknown actions, unsafe actions, stale state references, and low-confidence replacements.
   - Add hint expiry and latest-valid-hint selection.
   - Ensure the controller can run for at least 30 seconds without planner output.

9. Add AI harness model registry and router.
   - Define model registry schema with role, provider, model id, endpoint, capabilities, timeouts, prompt version, eval status, docs URL, and rollback id.
   - Route by job type, risk, privacy mode, latency tolerance, and failure history.
   - Keep literal model ids in registry data, not scattered through planner code.
   - Re-check official provider docs before implementation because model names and capabilities change.

10. Add the first provider-neutral AI harness adapter.
    - Start with OpenAI Responses API for slow-path structured planner hints.
    - Read credentials from environment.
    - Default privacy-sensitive calls to `store: false`.
    - Emit model-call trace events with role, provider, model id, prompt version, schema id, latency, timeout, validation status, and source trace/state ids.
    - Add timeout, cancellation, rate-limit, invalid-output, and provider-outage handling that leaves the controller running.

11. Add short-term and target memory.
    - Build short-term run memory in process for current goal, active hints, recent states, failures, user instructions, and safety stops.
    - Add target memory as scoped, source-linked JSONL records.
    - Require TTL or deliberate durable target scope.
    - Add deterministic approval for model-proposed memory writes.
    - Make memory records inspectable and deleteable by target, run, and user scope.

12. Add replay/eval for model and prompt changes.
    - Evaluate planner hints against recorded traces before promotion.
    - Track schema validity, hint acceptance, memory write acceptance, latency, cost, fallback count, and recovery success.
    - Add a model update checklist that records `last_verified_at`, docs URLs, eval suite id, and rollback model id.

13. Integrate slow planner beside the dry-run loop.
    - Trigger planner calls on scene change, low confidence, repeated failure, goal completion, or user instruction.
    - Build compact snapshots from world state, trace summaries, optional screenshots, and memory.
    - Publish only validated hints to the controller.
    - Prove planner latency does not move p95 reflex latency.

14. Enable guarded live-action smoke only after dry-run closeout.
    - Pick one target and one behavior.
    - Run end-to-end dry-run with input disabled and latency report passing.
    - Enable live input only with explicit policy allowance and focus guard.
    - Verify abort and timeout release held input.
    - Record trace evidence for every action.

15. Close out the primary plans.
    - Update supported behavior guides in `docs/guides/`.
    - Move `plans/20-off-the-shelf-run-loop.md` to `plans/done/` when the reflex loop acceptance criteria are supported.
    - Move `plans/19-ai-harness.md` to `plans/done/` when the AI harness acceptance criteria are supported.
    - Move supporting plans to `plans/done/` only if their acceptance criteria are fully satisfied; otherwise update them to describe the remaining future work.
    - Move this master plan to `plans/done/` after both primary plans are closed out.

## What Should Be Done Next

Start with task 4: add the first cheap perception adapter.

This is the right next slice because the current runtime now has lifecycle, event, artifact, manual capture, reflex trace, shared hot-loop contracts, a synthetic/recorded-frame dry-run skeleton, and bounded selected-window frame capture. It still needs a cheap deterministic perception adapter that converts fixture or target-window frame metadata into compact world state before controller replay can become target-shaped.

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
