# Synthetic Controller

> Archived status: historical context only. This file is not an active implementation queue. Supported behavior lives in `docs/`; future work from this idea needs a fresh active plan created deliberately.

## Goal

Build a generic synthetic input controller that emits calibrated input into a target game or app.

This layer should work across games by separating:

- semantic game actions
- normalized controller actions
- target-specific mappings
- OS or device-specific input backends

Touch gestures for iPhone Mirroring are one backend. A virtual gamepad is another backend. Keyboard/mouse is another.

This plan consolidates the previous standalone gamepad-controller sketch. Gamepad support is a backend and command family inside the broader synthetic controller, not a separate top-level architecture.

## Core Idea

The fast controller should not know about screen coordinates, key codes, HID details, or OS input APIs.

It should emit semantic actions:

```text
move_left
move_right
jump
roll
attack
interact
pause
release_all
```

The synthetic controller maps those actions through a target profile:

```text
move_left -> gamepad.dpad_left
move_right -> gamepad.left_stick_x = 1.0
jump -> gamepad.button_south
roll -> touch.swipe_down
interact -> keyboard.E
```

## Architecture

```text
Fast Controller
  -> Semantic Action
  -> Action Mapper
  -> Normalized Input Command
  -> Backend Adapter
  -> Game / App
```

Backends can include:

- macOS Accessibility tree/action backend
- gamepad / controller
- touch gestures
- keyboard
- mouse
- browser automation
- emulator API

## Normalized Command Interface

Generic commands:

```text
press(action, duration_ms)
hold(action)
release(action)
set_axis(axis, value)
tap(point, duration_ms)
swipe(direction, distance_px, duration_ms)
drag(start, end, duration_ms)
release_all()
stop()
```

Gamepad-shaped commands:

```text
press_button(button, duration_ms)
hold_button(button)
release_button(button)
tap_dpad(direction, duration_ms)
hold_dpad(direction)
release_dpad(direction)
set_left_stick(x, y)
set_right_stick(x, y)
set_left_trigger(value)
set_right_trigger(value)
neutralize_sticks()
release_all()
```

For low latency, axis updates should be cheap and avoid allocation.

Touch-shaped commands:

```text
tap(point, duration_ms=30)
double_tap(point, gap_ms=80)
swipe(direction, distance_px, duration_ms)
drag(start, end, duration_ms)
```

## Target Mappings

Each game should define a mapping file:

```text
target_id
backend
semantic_actions
bindings
timing
dead_zones
cooldowns
safety_rules
```

Example:

```text
target_id: subway-surfers-iphone-mirroring
backend: touch
move_left: swipe_left
move_right: swipe_right
jump: swipe_up
roll: swipe_down
hoverboard: double_tap_center
```

Example:

```text
target_id: generic-controller-game
backend: gamepad
move_left: left_stick_x=-1.0
move_right: left_stick_x=1.0
jump: button_south
attack: button_west
pause: button_menu
```

## Backend Selection

Pick the backend per target:

| Target Type | Preferred Backend |
| --- | --- |
| native Mac app with accessible controls | macOS Accessibility backend |
| native PC/Mac game with controller support | gamepad backend |
| emulator with API | emulator backend |
| iPhone Mirroring touch game | touch gesture backend |
| browser canvas game | mouse/keyboard or browser backend |
| DOM game/app | browser automation or DOM action backend |

If a game supports controllers, prefer the gamepad backend because it is usually more stable than screen-coordinate mouse gestures.

Important iPhone Mirroring caveat:

- Apple documents that wireless game controllers for iPhone apps should be connected to the iPhone, not the Mac.
- A Mac-side virtual controller may not control iPhone games through iPhone Mirroring.
- For iPhone games, gamepad automation may require a controller bridge paired directly to the iPhone, or the touch backend if controller bridging is not available.

## Gamepad Backend Shape

Use a common modern controller shape and keep vendor labels in mapping metadata:

```text
buttons:
  south
  east
  west
  north
  left_bumper
  right_bumper
  left_stick_button
  right_stick_button
  menu
  view
  home

dpad:
  up
  down
  left
  right

axes:
  left_stick_x  [-1.0, 1.0]
  left_stick_y  [-1.0, 1.0]
  right_stick_x [-1.0, 1.0]
  right_stick_y [-1.0, 1.0]
  left_trigger  [0.0, 1.0]
  right_trigger [0.0, 1.0]
```

Gamepad-specific mappings should support:

```text
jump -> press_button(south, 50ms)
dodge -> press_button(east, 50ms)
move_left -> set_left_stick(-1.0, 0.0)
move_right -> set_left_stick(1.0, 0.0)
aim_at -> set_right_stick(x, y)
shoot -> set_right_trigger(1.0)
stop_shoot -> set_right_trigger(0.0)
```

Possible gamepad backends:

- virtual gamepad device
- hardware controller bridge
- emulator controller API
- browser Gamepad API test harness
- platform-specific HID driver

## Backend Contract

Every backend should implement:

```text
connect()
is_available()
get_capabilities()
send(command)
release_all()
measure_latency()
disconnect()
```

Capabilities should declare:

```text
supports_buttons
supports_dpad
supports_analog_sticks
supports_triggers
supports_rumble
supports_low_latency
requires_focus
requires_pairing
```

## Calibration State

Store calibration separately from controller logic:

```text
target_id
target_window_id
target_window_title
backend
content_rect
display_scale
device_orientation
gamepad_layout
axis_dead_zones
button_hold_ms
gesture_distance_px
gesture_duration_ms
cooldowns
last_verified_at
```

## Timing Rules

- Use monotonic timestamps for every command.
- Do not queue stale commands.
- Enforce per-command deadlines.
- Prevent contradictory held inputs.
- Release held axes/buttons on stop.
- Rate-limit repeated taps, swipes, and button presses.
- Keep backend calls out of the perception loop.

Trace every command:

```text
action_id
semantic_action
normalized_command
backend
target_id
created_at
input_start_at
input_end_at
visual_confirmation_at
success
command_create_ms
backend_send_ms
device_update_ms
visual_response_ms
dropped_command_count
stale_command_count
held_input_duration
release_all_latency_ms
```

For controller games, visual response is the real proof that the backend works.

## Safety Rules

- Verify the target before input.
- Stop if the target window or device disappears.
- Stop if confidence is low.
- Stop on payment, login, system dialog, or unknown screen.
- Always support `stop()` and `release_all()`.
- Release all held buttons, keys, sticks, triggers, and mouse buttons on shutdown.

## Testing Plan

1. Build a local input visualizer target for each backend family.
2. Send every button, axis, key, pointer, and gesture command that the backend declares.
3. Verify neutral and release behavior.
4. Measure p50/p95 command-send latency.
5. Test one emulator, simple controller-friendly game, or touch target.
6. Add a target mapping.
7. Replay a recorded action trace.

## Acceptance Criteria

- The fast controller emits semantic actions, not backend-specific input.
- A target mapping can swap touch, keyboard/mouse, and gamepad backends without changing controller logic.
- Buttons, D-pad, sticks, and triggers are all supported in the normalized gamepad interface.
- Held inputs are always released on stop.
- Commands are timestamped and replayable.
- Backend latency is measured separately from decision latency.
- iPhone controller support is treated as a separate backend problem, not assumed through Mac iPhone Mirroring.
