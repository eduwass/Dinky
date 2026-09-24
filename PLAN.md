# dinky spike

Prove or disprove the mechanics of a SIP-on tiling window manager built on native macOS Spaces. Nothing else.

Machine: macOS 27.0 (26A428), SIP enabled. Full research, alternatives and the post-spike plan live in RESEARCH.md.

## The unknowns

Everything else in the earlier plan is known to work in some shipping window manager. Only these need proving on this OS build:

1. Moving a window to another native Space through the private bridged operation, with SIP on.
2. Switching Spaces fast enough to feel instant.
3. Raising one specific window of an app that has windows on both Spaces, without dragging its sibling along.

## Shape

A throwaway command-line tool, `dinky`, run from the terminal. No app bundle, no menu bar, no onboarding, no settings, no recovery journal, no animation. Accessibility is granted to the terminal once. Test windows are disposable TextEdit and Safari windows plus one terminal and one Electron app. If a window gets stranded, Mission Control can drag it back.

Swift package with one C/Objective-C target for the private calls and one Swift executable target. The private layer is lifted, not reimplemented:

| Need | Source to lift |
|---|---|
| Space list | `SLSCopyManagedDisplaySpaces`, yabai `src/space_manager.c` |
| Current Space, Space of a window | `SLSManagedDisplayGetCurrentSpace` and `SLSCopySpacesForWindows`, yabai `src/window.c` lines 61 to 93 |
| Windows on a Space | `SLSCopyWindowsWithOptionsAndTags`, yabai |
| Symbol lookup for the bridged dispatcher | mimi `internal/native/space.m`, `mimi_macho_find_symbol` and the resolve block around line 725 |
| Move windows to a Space | `SLSBridgedMoveWindowsToManagedSpaceOperation initWithWindows:spaceID:`, yabai `space_manager_move_window_to_space`. Both yabai and mimi fall back to `SLSMoveWindowsToManagedSpace` when the bridged call fails. Do not lift the fallback. |
| Swipe switching, Tuna form | Tuna `app/SystemExtension/SpacesRuntime.swift`. Already posts began/changed/ended, but sends multi-step swipes back to back with no delay and has no IOHID augmentation. |
| Swipe switching, mimi form | mimi `space.m` `mimiPostAugmentedDockSwipe` plus `dockswipe.m`. Adds the IOHID payload and waits between steps. |
| Direct switch, untested | `SLSBridgedManagedDisplaySetCurrentSpaceOperation initWithDisplayIdentifier:spaceID:` |
| Focus a specific window | yabai `src/window_manager.c` lines 1269 to 1330: `_SLPSSetFrontProcessWithOptions` plus `window_manager_make_key_window`. Not part of the scripting addition. |
| Stop apps animating AX frame writes | Clear `AXEnhancedUserInterface` on the app element before writing, yabai `src/misc/helpers.h` lines 516 to 529 |

Cached checkouts are under `~/.cache/checkouts/github.com/`.

## Preconditions

Before any step, in System Settings:

- Desktop & Dock, "Automatically rearrange Spaces based on most recent use": off. Otherwise Space indices change under the tool and step 2 means nothing.
- Record the values of "When switching to an application, switch to a Space with open windows for the application" and Accessibility, Reduce Motion. Both change what steps 2 and 4 show.

## Steps

Each step is one subcommand. Do them in order. Stop at the first gate that fails and write down why.

### 1. `dinky ls`

Print displays, the Spaces on the main display with the current one marked, and every normal window with its ID, app, title, frame and Space.

Gate: output matches what Mission Control shows.

### 2. `dinky switch <space-index>`

Try Tuna's swipe first. If the Dock ignores it, or multi-step swipes overshoot, port mimi's form. The bridged set-current-Space operation is a third path worth one attempt because it would remove the gesture entirely, but it is not required for the gate.

Latency is measured from posting to `SLSManagedDisplayGetCurrentSpace` reporting the target, polled on a tight loop. That flips before the switch animation finishes, so it is a lower bound, not the visual end.

Test: adjacent, two away, and ten rapid alternating switches.

Gate: at least one path lands on the requested Space every time, nothing jumps after input stops, and it subjectively feels as immediate as Hyprland. Record which path won and the measured latency.

### 3. `dinky move <window-id> <space-index> [--follow]`

Move one window through the bridged operation only. Confirm with `dinky ls` and with Mission Control, not with the return value.

Test: move away, move back onto the current Space from a hidden one, move and follow, move the frontmost focused window and note where focus goes, a window whose app has another window on the source Space, a window with a sheet open, and the same window moved back and forth five times quickly.

Gate: membership is correct in both `ls` and Mission Control after every case, the sibling stays put, the sheet travels with its window, and Dock and Mission Control stay coherent afterwards.

### 4. `dinky focus <window-id>`

Raise a specific window. Try AX raise plus app activation first, since that is the public path and the one expected to pull you over to the sibling's Space. Then try yabai's private focus path. Test with two windows of the same app on the same Space and again with one on each Space.

Gate: with at least one path, the requested window comes to front and the sibling on the other Space does not pull the current Space away. Record which path won and the switch-on-activate setting it was tested under.

### 5. `dinky tile`

Tile every normal window on the current Space through AX, then read frames back. The only layout code in the spike: sort windows by ID, split the rectangle along its longer side into two halves, give the first half of the list to one side and the rest to the other, recurse. No gaps. Clear `AXEnhancedUserInterface` first and write size, position, size, so Safari and Electron do not animate or clamp.

Gate: three windows land where computed, an app that rejects a size does not block the others, and switching between two tiled Spaces with `switch` feels like a working tiling WM.

## Deliberately not in the spike

App shell, permissions UI, recovery, accordion, layout tree, focus-follows-mouse, hotkeys, animation, multi-display, Space creation. All deferred to RESEARCH.md's phases, which only matter if all five gates pass.

## Decision

All five gates pass: start the real app from the RESEARCH.md phases, with the winning switch and focus paths and the measured latency as the baseline.

Step 1 fails: the private query layer does not match this build. Fix it or stop, nothing else can be trusted.

Step 2 or 3 fails: native Spaces are not a viable SIP-on backend on this build. Do not fall back to corner parking silently. Decide between waiting for a build where it works, or a different backend, as a separate conversation.

Step 4 fails: same-app windows across Spaces cannot be focused independently. The backend works but the accordion and any same-app workflow are compromised. Decide whether that is acceptable before building further.

Step 5 fails: the failure is in AX frame handling, which every shipping tiler has solved. Debug it, it is not evidence against the design.
