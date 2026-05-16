# Donkey

SwiftUI macOS app for the production pointer prompt UI.

This slice renders a floating native-cursor-sized agent arrowhead and compact prompt modal with a live voice waveform. Donkey starts in an inactive pointer-only state that follows the main pointer. Double-tap Command and release to show and focus the prompt modal at the current pointer location, where the pointer and modal stay pinned while live microphone levels drive the waveform. The prompt starts as a wide pill, expands into a rounded rectangle for multiline text, and moves the waveform into a bottom toolbar that matches the input background. Clicking outside the modal dismisses it, and a small gray circular x button at the top-right outside corner closes it directly. The overlay follows the mouse on a 45-degree bottom-right diagonal by default.

It requests microphone permission for local waveform visualization. It does not request Accessibility, Screen Recording, model access, screen capture-loop, or input-control permissions.

Guides:

- [Pointer Prompt Overlay](../../docs/guides/pointer-prompt-overlay.md)
- [Swift MVC Guide](../../docs/guides/swift-mvc.md)

```sh
swift build
swift run Donkey
```

Customize the pointer colors in [Sources/Donkey/Resources/theme.json](Sources/Donkey/Resources/theme.json). The app supports `#RRGGBB` and `rgba(r, g, b, a)` color strings.
