# Donkey

SwiftUI macOS app for the production pointer prompt UI.

This slice renders a floating native-cursor-sized agent arrowhead and ChatGPT-style `Make this so` composer. Donkey starts in an inactive pointer-only state that follows the main pointer. Command-click anywhere to show and focus the composer at the current pointer location, where the pointer and composer stay pinned until dismissed or dragged. The composer includes a top-left close button, a text area, and controls such as add context, voice, and send; the blue pointer shadow appears only while active. The overlay follows the mouse on a 45-degree bottom-right diagonal by default, flips around an invisible cursor-centered box near screen edges, and clamps itself inside the visible screen.

It does not request Accessibility, Screen Recording, model access, capture-loop, or input-control permissions.

Guides:

- [Pointer Prompt Overlay](../../docs/guides/pointer-prompt-overlay.md)
- [Swift MVC Guide](../../docs/guides/swift-mvc.md)

```sh
swift build
swift run Donkey
```

Customize the pointer colors in [Sources/Donkey/Resources/theme.json](Sources/Donkey/Resources/theme.json). The app supports `#RRGGBB` and `rgba(r, g, b, a)` color strings.
