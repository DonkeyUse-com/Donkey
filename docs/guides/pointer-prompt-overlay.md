# Pointer Prompt Overlay

## Supported Behavior

Donkey supports a floating macOS pointer prompt overlay:

- shows a small inactive agent pointer that follows the user pointer immediately when Donkey starts
- double-tap Command and release to activate and focus a compact prompt modal at the current pointer location without clicking into the target app
- double-tap Command and hold the second Command press to activate voice input
- shows a native-cursor-sized agent arrowhead and a black prompt modal with text input and a white voice waveform while active
- uses a wide pill-shaped prompt for single-line text, then expands to a rounded rectangle when text wraps at the max input width or the user inserts new lines
- places the waveform and toolbar affordances in a bottom toolbar that uses the same background color as the input when the prompt is expanded
- captures microphone audio while active and renders the waveform from recent live audio levels
- keeps the pointer and prompt modal pinned where activation happened until the user drags, dismisses, or closes the modal
- dismisses the active modal when the user clicks outside it
- closes the active modal with a small gray circular x button outside the prompt surface at the top-right corner
- supports dragging the active modal from capsule areas outside the text input
- lets normal clicks pass through the inactive pointer-only overlay and transparent active overlay space
- follows the user mouse at a fixed 45-degree bottom-right diagonal
- keeps that fixed offset at screen edges instead of flipping or clamping to the visible screen bounds
- renders a shadow underneath the agent pointer when active
- supports user-accessible theme customization through `apps/Donkey/Sources/Donkey/Resources/theme.json`
- keeps runtime and AI harness behavior behind explicit integration boundaries

This is a visual and microphone-level UI capability. It does not capture the screen, send input, call models, or require Accessibility permission. It does request microphone permission so the waveform can reflect live local audio levels.

## Technical Guidelines

- The overlay window is an `NSPanel` owned by `PointerPromptOverlayController`.
- Donkey runs with the accessory activation policy, and prompt focus must make the app active, make the panel key, then make the composer text view first responder. A blinking insertion point alone does not mean macOS is sending keyboard events to the panel.
- SwiftUI rendering stays in `DonkeyUI`; it receives `PointerPromptState` and `PointerPromptPlacement` from `DonkeyContracts`.
- Product state stays in `PointerPromptOverlayModel`.
- Treat the active modal as a compact black prompt surface with a text input, embedded waveform, and a small gray circular x button perched outside the surface at the top-right corner. It has no separate voice button.
- Single-line input should render as a full pill. Multiline input should render as a rounded rectangle with non-pill corners and a bottom toolbar matching the input background, containing the waveform and lightweight control affordances.
- Text wraps at the prompt width. Return submits typed text. Shift-Return inserts a deliberate newline.
- The controller owns microphone capture and publishes normalized audio levels into product state; SwiftUI only renders the levels it receives.
- Pointer colors load from JSON into `PointerPromptTheme`; views must not hard-code product colors.
- The active prompt modal should use a capsule shape and keep transparent active overlay space passing clicks through to windows underneath after it dismisses.
- The active modal top edge should align with the highest visible point of the agent pointer.
- The agent pointer should remain close to native cursor size, use the mirrored SVG cursor silhouette from the Noun Project pointer asset, point in the same up-left direction as the native macOS cursor, and keep its tip 48px from the real pointer on an equal x/y diagonal.
- Runtime placement is fixed to `bottomRight`; alternate `PointerPromptPlacement` values are only rendering variants.
- The controller must not clamp visible pointer/modal bounds to `NSScreen.visibleFrame`; cursor positioning is a direct fixed-offset calculation.
- Launch positioning and double-Command activation handling belong in `PointerPromptOverlayController`, not the SwiftUI view.
- Double-Command is the only active shortcut today. Its default lives in `PointerPromptActivationShortcut.doubleCommand` so a future settings layer can supply a different shortcut without rewriting controller event handling.
- Double-Command prompt activation should require two clean Command down/up taps within 450ms. Any intervening key press, mouse press, extra modifier, or overlong Command hold should reset the sequence so normal shortcuts do not summon the modal.
- Holding the second clean Command press for the shortcut's configured hold duration should activate the prompt modal and start microphone level capture instead of waiting for the second release.
- Keep the overlay non-invasive: no screen capture loop, input execution, Accessibility prompt, or LLM call in this feature.

## Verification

From `apps/Donkey/`:

```sh
swift build
swift run Donkey
```

Launch Donkey and confirm only the small agent pointer appears and follows the main pointer at a fixed bottom-right diagonal offset. Double-tap Command and release to show the black prompt capsule with keyboard focus, grant microphone permission if prompted, then speak or tap near the microphone and confirm the waveform responds to real audio levels. Type enough text to wrap and confirm the prompt changes from a pill into a rounded rectangle, grows downward while its top edge stays fixed, and moves the waveform into a blended bottom toolbar. Press Shift-Return and confirm it inserts a newline; press Return and confirm it submits. Move the mouse and confirm the active pointer and modal stay pinned. Double-tap Command again but hold the second Command press, and confirm the same prompt modal appears. Click outside the active modal and confirm it dismisses. Reactivate, click the gray rounded x button outside the capsule, and confirm it closes. Drag the modal from non-input capsule areas. Activate near the bottom-right screen edge to confirm the prompt keeps the same fixed offset instead of flipping or clamping. Confirm Command plus another key, Command-click, and a single Command tap do not activate the modal.

To verify color customization, edit `apps/Donkey/Sources/Donkey/Resources/theme.json`, rebuild, and run Donkey.

## Source Entry Points

- App orchestration starts in `apps/Donkey/Sources/Donkey/`.
- Reusable SwiftUI rendering lives in `apps/Donkey/Sources/DonkeyUI/`.
- Historical completion notes live in `plans/done/21-swiftui-pointer-ui.md`.
