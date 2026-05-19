# macOS Accessibility

> Archived status: this slice is implemented. Supported behavior lives in `docs/`; future work needs a fresh active plan created deliberately.

## Completed Slice

Donkey now treats iPhone Mirroring as an ordinary Mac window candidate. Window discovery builds runtime app identity from the current `NSWorkspace` running-app map, enriches each visible window by pid, and keeps iPhone Mirroring as an additive hint instead of a separate discovery path.

The implemented accessibility/window slice covers:

- content-rectangle calibration for mirrored iPhone content inside the selected generic target window
- generic target-window focus, process, bundle, bounds, visibility, and safety guarding before synthetic input
- timeout-bounded Accessibility snapshot reads and Accessibility action execution
- native macOS dialog detection from Accessibility trees as a safety stop

## Current Boundary

Accessibility still describes the Mac-side container and native dialogs. It does not inspect iPhone game internals inside the mirrored video stream. Live gameplay perception remains screenshot/model driven, with the calibrated content rectangle feeding the capture/control loop.

No remaining implementation queue is tracked in this plan.
