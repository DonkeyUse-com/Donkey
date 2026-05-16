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

- Add a macOS target resolver that can enumerate and describe candidate windows:
  - pid
  - app name or bundle id when available
  - window title
  - bounds in screen coordinates
  - focus/frontmost status
- Support explicit targeting by window id, pid/title tuple, or selected candidate from a debug UI/command.
- Use the focused window only as a default when no explicit target is provided.
- Treat iPhone Mirroring as a normal candidate window with optional target-specific metadata.
- Stop and record a safe failure if the target appears to be a system prompt, payment/login surface, or unknown sensitive window.

### Screenshot Capture

- Start with one manual screenshot per run.
- Capture the explicitly selected target window bounds, not the whole desktop by default.
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
- Accessibility tree capture is shallow, bounded, and serializable.
- Missing Accessibility permission produces a clear event and a partial run summary instead of crashing.
- Input and Accessibility actions remain disabled.
- Sensitive/system/payment/login windows are refused or marked as safety stops.
- Unit tests cover metadata serialization, run artifact path generation, artifact summary updates, bounded AX tree serialization, and policy denial for input.
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

Continue the read-only vertical slice from the completed local artifact writer:

1. Add window enumeration and target selection metadata.
   - Add a macOS window resolver in `DonkeyRuntime` that returns visible candidate windows with window id, pid, app name or bundle id, title, bounds, and frontmost/focus metadata.
   - Support explicit selection by window id and a focused-window default when no explicit target is provided.
   - Treat iPhone Mirroring as a normal visible candidate, not a special-only path.
   - Add conservative safety metadata so later capture can refuse obvious system, login, payment, or unknown sensitive surfaces.
   - Add tests for metadata serialization, target selection rules, focused-window fallback, and safety classification.
2. Add one target-scoped screenshot artifact.
   - Capture the selected target bounds, write PNG bytes through `LocalRunArtifactStore`, and record screenshot artifact metadata.
3. Add shallow Accessibility tree capture behind permission checks.
   - Serialize a bounded AX snapshot when trusted and record a clear partial-run event when not trusted.
4. Wire the manual capture flow through `RunCoordinator` events.
   - Emit ordered lifecycle/tool events for target resolution, screenshot capture, AX snapshot, artifact persistence, completion, and failure paths.
5. Add integration tests and manual verification.
   - Cover artifact metadata, bounded AX serialization, policy denial for input, and partial summaries.
   - Manually verify against iPhone Mirroring and at least one other visible Mac app window.
