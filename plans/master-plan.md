# Manual Target Context Capture Master Plan

## Goal

Build the first read-only data capture milestone for Donkey runs.

One manual command or UI action should create a run session, select any visible target window, capture a screenshot, dump a shallow macOS Accessibility tree, write trace artifacts, and publish ordered runtime events.

This should prove the data path before continuous capture, perception models, or synthetic input are added.

## Master Plan Role

Use this document as the current active master plan for the next sequence of work.

It coordinates the order of plan edits and implementation slices needed to move Donkey from a runtime coordinator shell into real target-window context capture. Start here before editing the older active plans.

Edit sequence:

1. Keep this plan as the implementation driver until manual target context capture is supported.
2. Update [18-macos-accessibility.md](18-macos-accessibility.md) only for Accessibility details that are still future-facing after read-only AX snapshots exist.
3. Update [02-capture-and-perception.md](02-capture-and-perception.md) only for capture/perception boundaries that remain after manual screenshots are supported.
4. Update [06-benchmarking.md](06-benchmarking.md) only for trace/artifact measurement rules that remain broader than this milestone.
5. Update [20-off-the-shelf-run-loop.md](20-off-the-shelf-run-loop.md) only for the larger runtime/perception loop that remains after the minimal coordinator and manual capture pieces are documented.
6. When this milestone is implemented, write or update the supported guide in `docs/guides/`, then move this plan to `plans/done/`.

Do not spread implementation instructions across multiple active plans while this one is still open. Use linked plans for background and cleanup targets, not as competing sources of truth.

## Related Plans And Guides

- [20-off-the-shelf-run-loop.md](20-off-the-shelf-run-loop.md): runtime shell, event streams, session lifecycle, and coordinator boundary
- [18-macos-accessibility.md](18-macos-accessibility.md): Accessibility tree/action backend and iPhone Mirroring window guard
- [02-capture-and-perception.md](02-capture-and-perception.md): screenshot capture and world-state direction
- [06-benchmarking.md](06-benchmarking.md): trace events, timestamps, and run artifact shape
- [12-iphone-mirroring.md](12-iphone-mirroring.md): first target surface for mobile-game capture
- [../docs/guides/minimal-run-coordinator.md](../docs/guides/minimal-run-coordinator.md): supported run coordinator behavior

## Scope

Build a manual, read-only capture flow:

```text
prompt / debug command
  -> RunSession
  -> target window resolver
  -> screenshot capture
  -> Accessibility tree snapshot
  -> trace artifact write
  -> RunCoordinator tool/lifecycle events
  -> compact context summary
```

In scope:

- enumeration and selection of any visible macOS window
- active, focused, or explicitly selected window metadata
- iPhone Mirroring as one supported target option, not a special-only path
- screenshot artifact metadata and PNG output
- shallow Accessibility tree snapshot with roles, labels/titles, values, frames, pid, and window metadata
- local trace folder for one run, stored under Application Support by default
- ordered runtime events for capture and persistence
- privacy-oriented redaction boundaries for sensitive windows

Out of scope:

- continuous frame capture
- OCR, object detection, SAM, or model inference
- synthetic input or Accessibility actions
- remote model calls
- full desktop recording
- hot-loop performance optimization

## Implementation Plan

### Runtime And Permission Integration

- Add a capture-facing service in `DonkeyRuntime` that works with `RunCoordinator`.
- Extend the current tool capability policy only as needed for read-only capture:
  - screenshot/window capture
  - Accessibility tree read
  - trace persistence
- Keep input/action capabilities denied by default.
- Emit `tool` events for target resolution, screenshot capture, Accessibility snapshot, and artifact persistence.
- Emit `lifecycle` events for manual capture start, completion, abort, timeout, and failure.

### Target Window Resolution

Supported as the second vertical slice. `MacWindowResolver` enumerates visible on-screen macOS app windows, normalizes window metadata, supports explicit selection by window id, falls back to the focused/frontmost candidate, marks iPhone Mirroring as a normal candidate with a hint, and attaches conservative safety metadata.

Current boundaries:

- Window candidate numbering is not durable. A debug UI or command should map short labels like "window 1" to the candidate's macOS `windowID` at the time the user chooses.
- Selection by pid/title tuple is still future-facing. Current deterministic selection is explicit window id or focused/frontmost fallback.
- Safety classification is metadata-only. Later capture orchestration must refuse or safety-stop blocked/review-required targets before writing screenshots.
- Overlap is not solved by metadata alone. Screenshot capture must avoid accidentally recording another window that visually covers the selected target.

### Screenshot Capture

- Start with one manual screenshot per run.
- Capture the explicitly selected target window, not the whole desktop by default.
- Prefer a true window-scoped capture path when available so overlapping windows do not contaminate the artifact.
- If the first implementation must use a bounds crop, validate that the selected target is frontmost/focused immediately before capture, record the capture method as overlap-sensitive, and safety-stop when another visible window appears to cover the target bounds.
- Store screenshots under the prepared run folder:

```text
<run-folder>/screenshots/<artifact-id>.png
```

- Write sidecar metadata:
  - artifact id
  - run id
  - trace id
  - monotonic and wall-clock timestamps
  - target/window metadata
  - coordinate space
  - image size
  - capture method
  - occlusion/overlap validation result when available

### Accessibility Tree Snapshot

- Add an Accessibility adapter that can:
  - check trust status
  - get frontmost/focused app and window
  - resolve a selected target window by pid/title/window metadata when possible
  - read a shallow AX tree with bounded depth and child count
  - serialize role, title/label, value summary, frame, enabled/focused state, and action names
- Store AX snapshots under the prepared run folder:

```text
<run-folder>/accessibility/<artifact-id>.json
```

- Keep the tree bounded. Do not dump arbitrarily large app trees.
- Redact long text values by default and store summaries instead of full sensitive text.

### Trace Artifact Store

Supported as the first vertical slice. `LocalRunArtifactStore` prepares durable run folders, appends JSONL event records, reserves safe artifact paths, records artifact metadata, and updates summaries.

Installed Donkey stores runs under:

```text
~/Library/Application Support/Donkey/Runs/<run-id>/
```

Tests and development tools may pass an explicit base directory override. Each run folder contains:

```text
events.jsonl
summary.json
screenshots/
accessibility/
```

- Keep the artifact store simple and local for this milestone. It can become async or buffered after coordinator capture events are wired to disk.

### Context Assembly

- Feed compact artifact references into context assembly:
  - screenshot artifact ids and target metadata
  - Accessibility tree summary
  - recent capture failures
  - run goal and target id
- Do not pass raw screenshots or full AX trees to an LLM yet.

## Acceptance Criteria

- A manual command or prompt action creates a run session and one trace folder.
- The trace folder contains `events.jsonl`, `summary.json`, one screenshot artifact, and one Accessibility snapshot when permission is available.
- The capture flow records ordered `tool` and `lifecycle` events through `RunCoordinator`.
- Screenshot capture is target/window scoped by default.
- Overlapping windows do not silently produce misleading target screenshots. The capture path either uses true window capture or records/refuses an overlap-sensitive bounds crop when the target is occluded.
- Accessibility tree capture is shallow, bounded, and serializable.
- Missing Accessibility permission produces a clear event and a partial run summary instead of crashing.
- Input and Accessibility actions remain disabled.
- Sensitive/system/payment/login windows are refused or marked as safety stops.
- Unit tests cover metadata serialization, target selection rules, run artifact path generation, artifact summary updates, bounded AX tree serialization, overlap/occlusion safety behavior, and policy denial for input.
- Manual verification works against at least two different windows, such as iPhone Mirroring and a normal Mac app window.

## Handoff Notes For The Next LLM

- Before implementing, re-read `docs/README.md`, `docs/guides/minimal-run-coordinator.md`, `plans/18-macos-accessibility.md`, and `plans/20-off-the-shelf-run-loop.md`.
- Keep this plan active while manual capture is incomplete.
- When this milestone is complete, create or update a supported guide in `docs/guides/` for data capture and Accessibility snapshots.
- After the guide exists and tests/manual verification pass, move this plan to `plans/done/`.
- Clean up overlapping completed details in active plans:
  - keep `plans/20-off-the-shelf-run-loop.md` focused on future off-the-shelf perception and runtime direction
  - avoid duplicating the already-supported minimal coordinator behavior from `docs/guides/minimal-run-coordinator.md`
  - keep `plans/18-macos-accessibility.md` focused on future AX actions/window guards once read-only AX capture is documented
- Prefer shrinking active `plans/` when a capability becomes supported. Completed implementation facts should live in `docs/guides/`, not in long active plan sections.

## What Should Be Done Next

Continue the read-only vertical slice from the completed local artifact writer and window resolver:

1. Add one overlap-aware target screenshot artifact.
   - Resolve a `MacWindowTargetCandidate` from an explicit `windowID` or the focused/frontmost fallback.
   - Refuse or safety-stop before capture when the target safety status is blocked or review-required.
   - Prefer true window capture over bounds cropping so overlapping windows do not contaminate the selected target artifact.
   - If bounds cropping is the only available first implementation, add occlusion checks from the ordered window list and refuse/record a partial run when another visible window overlaps the selected target.
   - Write PNG bytes through `LocalRunArtifactStore` and record screenshot artifact metadata, including target metadata, capture method, coordinate space, image size, and overlap validation result.
   - Add tests with fixture window providers for safe capture, blocked target refusal, and occluded bounds-crop refusal.
2. Add candidate-list support for manual/debug selection.
   - Provide a small read-only API that returns ordered visible candidates with ephemeral labels such as `window 1`, `window 2`, and their durable `windowID` values.
   - Make clear that labels are valid only for the current enumeration snapshot; follow-up commands should carry the durable `windowID`.
   - Add tests that labels remain deterministic for one snapshot and that explicit `windowID` selection is used for multi-window flows.
3. Add shallow Accessibility tree capture behind permission checks.
   - Serialize a bounded AX snapshot when trusted and record a clear partial-run event when not trusted.
4. Wire the manual capture flow through `RunCoordinator` events.
   - Emit ordered lifecycle/tool events for target resolution, screenshot capture, AX snapshot, artifact persistence, completion, and failure paths.
5. Add integration tests and manual verification.
   - Cover artifact metadata, bounded AX serialization, policy denial for input, and partial summaries.
   - Manually verify against iPhone Mirroring and at least one other visible Mac app window, including an overlapped-window scenario.
