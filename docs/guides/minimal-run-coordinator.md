# Minimal Run Coordinator

## Supported Behavior

Donkey supports a minimal in-memory runtime coordinator for the future off-the-shelf run loop.

The coordinator can:

- accept run sessions with a user goal, target id, runtime profile, and permission policy
- keep only the latest pending live-control session request
- publish ordered `assistant`, `tool`, `lifecycle`, and `reflex` events
- move through explicit lifecycle states for start, pause, resume, completion, abort, timeout, and failure
- deny unsafe input tool calls by default
- mark aborts and timeouts as requiring held-input release
- build bounded planner context from the current session, world-state summary, transcript summary, valid hints, and recent failures

Donkey also supports a local run artifact store for durable trace data. Installed app runs are stored under `~/Library/Application Support/Donkey/Runs/<run-id>/`; tests and development tools may pass an explicit base directory override. Each prepared run creates:

```text
events.jsonl
summary.json
screenshots/
accessibility/
```

The artifact store can append ordered event records, reserve safe screenshot or Accessibility artifact paths, record artifact metadata, and keep `summary.json` current.

Donkey can also resolve visible macOS target-window metadata for the manual capture path. The resolver enumerates on-screen app windows, describes window id, pid, app name, bundle id, title, bounds, focus/frontmost state, iPhone Mirroring hints, and conservative safety metadata. Callers can select an explicit window id or fall back to the focused/frontmost visible window.

Donkey can create a single read-only target-window screenshot artifact after a run folder has been prepared. The screenshot service resolves the target, refuses blocked or review-required safety surfaces, captures the selected window with ScreenCaptureKit's desktop-independent window path, writes PNG bytes under `screenshots/`, and records flattened target/capture metadata in `summary.json`. Overlap-sensitive fallback capture backends must refuse occluded targets instead of silently recording pixels from another window.

This is a coordination, trace, target-metadata, and single-screenshot artifact foundation only. It does not dump Accessibility trees, run perception models, call LLMs, execute OS input, provide a manual capture UI, or wire coordinator events into disk persistence yet.

## Technical Guidelines

- Keep shared event, policy, lifecycle, and context types in `DonkeyContracts`.
- Keep coordinator state and append ordering in `DonkeyRuntime`; UI code should read status through narrow provider boundaries.
- Treat `RunCoordinator` as the owner of lifecycle and event ordering, not as the owner of perception, controller internals, or input backends.
- Treat `LocalRunArtifactStore` as a persistence sink for trace records and artifact metadata. It should not own lifecycle state or decide whether tool calls are allowed.
- Treat macOS window resolution as read-only metadata collection. Safety classifications should be conservative and used by later capture code to refuse or stop on sensitive surfaces.
- Treat target-window screenshot capture as a one-shot artifact write, not a continuous capture loop. ScreenCaptureKit desktop-independent window capture is preferred because overlapping windows do not contaminate the selected target artifact.
- Keep mutable installed-app run artifacts in Application Support, not inside the `.app` bundle and not relative to process working directory.
- Keep input actions denied unless a caller provides a policy that explicitly allows them.
- Preserve latest-request-wins behavior for live-control sessions so stale work cannot build up behind the reflex loop.
- Use sampled or summarized reflex events until a measured trace sink exists.

## Verification

From `apps/Donkey/`:

```sh
swift test
```

The runtime tests should cover lifecycle ordering, abort and timeout safety, latest-session queue drops, tool permission denial, event-store ordering, context compaction, artifact path validation, trace folder layout, JSONL event persistence, summary updates, deterministic window resolver behavior through fixture providers, screenshot artifact metadata, unsafe target refusal, and overlap-sensitive capture refusal.

## Source Entry Points

- Runtime contracts live in `apps/Donkey/Sources/DonkeyContracts/RunLoopContracts.swift`.
- Window target contracts live in `apps/Donkey/Sources/DonkeyContracts/WindowTargetContracts.swift`.
- Runtime coordination lives in `apps/Donkey/Sources/DonkeyRuntime/`.
- macOS window resolution lives in `apps/Donkey/Sources/DonkeyRuntime/MacWindowResolver.swift`.
- Target-window screenshot capture lives in `apps/Donkey/Sources/DonkeyRuntime/WindowScreenshotCaptureService.swift`.
- Local artifact persistence lives in `apps/Donkey/Sources/DonkeyRuntime/LocalRunArtifactStore.swift`.
- The manual capture source plan remains active in `plans/master-plan.md`.
