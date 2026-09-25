# Spike results

Run on 24 September 2026 in a Tart VM (`dinky`, cloned from `tuna-golden-gate-base`): macOS 27.0 build 26A5416b, SIP **disabled** (how the Cirrus Labs images ship), 1024x768 display at 2x, admin logged in on the console. The binary was built on the host (27.0 build 26A428, SIP on) and copied in. Commands ran over SSH with Accessibility, Screen Recording, Post Event and Apple Events granted to `/usr/libexec/sshd-keygen-wrapper` in the guest's TCC database. `mru-spaces` was set to false; the switch-on-activate setting and Reduce Motion were left at defaults.

The host itself has not been tested. Both differences from the plan's target (beta build, SIP off) should be closed by rerunning on the host.

## Step 1, `ls`: pass

Displays, Spaces and window membership matched Mission Control throughout.

## Step 2, `switch`: pass via mimi's swipe

| Path | Adjacent | Two away | 10 rapid alternations |
|---|---|---|---|
| Tuna swipe | timeout, Dock ignores it | timeout | not run |
| mimi augmented swipe | lands, screen changes | lands | min 41, median 66, max 99 ms, 0 timeouts |
| bridged set-current-Space | see below | not run | 13 to 34 ms but see below |

Tuna's form (no IOHID payload) is ignored by the Dock on this build, as mimi's comments say. mimi's form with the serialized IOHID payload and velocity 9999 works every time. Two-away switches take about 128 ms median because mimi waits 30 ms between steps.

The bridged `SLSBridgedManagedDisplaySetCurrentSpaceOperation` changes the Space ID that SkyLight reports but only sometimes changes the screen. Pixel sampling showed it never switched the display from Space 1 to 2, even after 3 s and a click, while it did switch from 2 back to 1 every time. Not usable.

Latency is measured to `SLSManagedDisplayGetCurrentSpace` flipping, a lower bound on the visual switch.

## Step 3, `move`: pass

All through `SLSBridgedMoveWindowsToManagedSpaceOperation`, no fallback. Every case landed in 3 to 14 ms with membership correct in `ls` and in Mission Control:

- move away, move back from the hidden Space, move and follow (follow via mimi swipe, 78 ms)
- frontmost window moved away: the app stays frontmost, the current Space does not change
- one TextEdit window moved while its sibling stayed on the source Space
- a TextEdit window with a Save sheet open: the sheet moved with it and was usable on the other Space
- the same window moved back and forth 5 times: all landed, max 10 ms

## Step 4, `focus`: pass with a caveat

- AX raise plus activate: hits for two windows of one app on the same Space, and with the sibling on another Space, without changing the Space.
- yabai's private path alone often misses when the app is not frontmost. With an AX raise added after it, which yabai also does, it hits in every same-Space case.
- Neither path can focus a window on another Space. AX does not list it, and the private path does nothing. Neither pulls the current Space away. A window manager must switch first, which is what we want.

## Step 5, `tile`: pass

Five windows on Space 1 landed where computed except for known size refusals: Safari enforces a 574 pt minimum width in a 512 pt column, and Terminal snaps to its character grid. Neither blocked the other windows. Two Spaces tiled separately and switched between with mimi's swipe felt like a working tiler in screenshots.

## Decision

All five gates pass on this VM. The winning paths are mimi's augmented Dock swipe for switching, the bridged operation for moving, and AX raise for focus. Rerun on the host with SIP on before starting the real app.

## Addendum, 25 September: Mission Control's own shortcuts instead of the swipe

Added `--path keys` (Control-Left/Right, one keystroke per step) and `--path number` (Control-N). Findings in the same VM:

- Synthetic Control-Arrow is ignored unless the events carry the secondary-fn flag as well as Control (the hotkey is registered with flags 0x840000, since arrow keys carry fn on Apple keyboards). Modifier flags-changed events alone do not help. With the fn bit it works every time.
- Control-N is off by default. Enabling symbolic hotkeys 118 to 120 through `defaults` and restarting the Dock or running `activateSettings -u` did not take effect within the session, so it was not measured.
- Latency, Control-Arrow, adjacent, 10 alternations: min 554, median 558, max 601 ms to the Space ID flip. Two away: about 610 ms. Two keystrokes posted back to back: 738 ms, and it lands on the right Space.
- Visual settle, sampled every 100 ms: the target Space is on screen by about 290 ms with the keys path, and the Space ID flips only when the slide animation ends. With mimi's swipe the screen has already changed at the first 32 ms sample.
- Reduce Motion set through `defaults` made no measurable difference, but that setting may also need a logout to apply.

The keyboard route is the plain, supported way to switch and it works, but it is roughly 10x slower to the eye than the high-velocity swipe, which skips the animation entirely.

## Addendum, 25 September: Cmd-Tab and Dock activation

Cmd-Tab or a Dock click on an app whose windows are on another Space makes macOS switch there with its own slide, because of the "When switching to an application, switch to a Space with open windows" setting (`com.apple.dock workspaces-auto-swoosh`). With the setting on, activating TextEdit from another Space took about 294 ms to the Space ID flip, plus the animation.

With the setting off, macOS only activates the app. The `dinky hotkeys` daemon now observes `NSWorkspace.didActivateApplicationNotification`, finds the app's frontmost normal window through the CG window list and its Space through SkyLight, and swipes there with the mimi path. Measured through a coarse polling loop: TextEdit 77 ms, Terminal 62 ms, with the app frontmost afterwards. So every route to another Space, keyboard, Cmd-Tab or Dock, can go through the fast switch. Not yet tested: apps with windows on several Spaces, activation of an app with no windows, and what the real Cmd-Tab switcher does versus `open -a`.

## Display targeting for switching

Research from source only; there is no two-display machine to test on, and the VM has one display. Checkouts: mimi 1107d3e, yabai dd84572, bobrwm 537627f, Tuna as of 25 September.

**1. Which display the Dock swipes.** The display under the cursor. None of the four projects routes the swipe any other way:

- mimi `MimiFocusSpaceUsingGesture` (internal/native/space.m:487) finds the cursor's display (`mimiCursorDisplayID`, space.m:110-124, `SLSGetCurrentCursorLocation` plus `CGGetDisplaysWithPoint`) and warps if the target differs (space.m:493-502). Its comment at space.m:504-506: "Swipe gestures navigate spaces on the active display only", which is why it computes indices on the target display only after the warp.
- yabai's SIP-on path, `space_manager_focus_space_using_gesture` (src/space_manager.c:927-983, added 18 April 2026 in 7c4c5ba "#2780 implement space --focus with SIP enabled"), does the same: `cur_did = display_manager_cursor_display_id()` (display_manager.c:232-237), then `if (focus_display) CGWarpMouseCursorPosition(point);` (space_manager.c:939-942). `space_manager_focus_space` falls back to it when the scripting addition is unavailable (space_manager.c:1001-1006).
- bobrwm `routeDockSwipeToDisplay` (src/skylight.zig:843-859), called before any multi-step swipe (skylight.zig:251), returns early when the cursor is already on the display and otherwise warps to the display's centre. The function name states the assumption.
- Tuna has no targeting at all. `cursorDisplayIdentifier` (app/SystemExtension/SpacesRuntime.swift:146-155) takes `CGEvent(source: nil).location` and passes that display to `CGSCopyManagedDisplaySpaces` (SpacesRuntime.swift:55-63) only to read the current index and count; the swipe itself (SpacesRuntime.swift:109-143) carries no display. It works because the Dock swipes that same cursor display.

**2. Does the event name a display?** No. The CGEvent fields set are the type, HID type, motion, phase and phase alias, progress, `PositionX` = 0.1, `ZoomDeltaY` = 3 and, on the ended phase, velocity (mimi space.m:360-366 and 431-449). `PositionX` is a normalised trackpad position ("empirically required", space.m:365), not a screen point, and `PositionY` is never set. Field 169, `kCGEventSourceUnixProcessIDAlias`, gets `mach_absolute_time()` (space.m:443), a timestamp-like value rather than a display. The IOHID payload (mimi dockswipe.m:23-58, filled at 136-145) is a queue header (timestamp, a `senderID` left at 0, options, event count) plus a fluid-touch gesture record (position, swipe mask, motion, flavor, progress) and a velocity record, with no display field. So the only display information the Dock gets is where the cursor is: the event's location, which `CGEventCreate(NULL)` fills with the current pointer position, or the WindowServer's own cursor position. Not the display with the key window: all three projects that target a display move the cursor, not focus.

**3. What each does when the target is not the cursor's display.**

- mimi warps and does not restore the cursor: `CGWarpMouseCursorPosition(point);` then `mimiPumpRunLoop(kMimiSpaceGestureProcessingDelay);` (30 ms, space.m:497-502), posts the swipes, waits (space.m:579), then `mimiSetActiveMenuBarDisplay(new_did)` (`SLSSetActiveMenuBarDisplayIdentifier`, space.m:128-136) and, if the display's Space is still wrong, a synthetic left click at the display centre (space.m:580-594). There is one `CGWarpMouseCursorPosition` in the file and no restore.
- yabai: the same without the wait. `if (focus_display) CGWarpMouseCursorPosition(point);`, the swipes, then `display_manager_set_active_display_id(new_did); if (space_manager_active_space() != new_sid) { CGPostMouseEvent(point, false, 1, true); CGPostMouseEvent(point, false, 1, false); }` (space_manager.c:942-980). No restore. `CGAssociateMouseAndMouseCursorPosition` appears nowhere in yabai (nor in mimi, bobrwm or Tuna).
- bobrwm: warp only, `return c.CGWarpMouseCursorPosition(center) == c.kCGErrorSuccess;` (skylight.zig:858). No restore, no menu bar or click follow-up.
- Tuna: nothing; it always acts on the cursor's display.

**What dinky does now** (Sources/DinkyPrivate/switch.m). `dinky_switch_to_space_index` looks up `displayUUID` in `dinky_displays()` and refuses with `switch: no display with UUID ...` on stderr when it is not there, for every path. The mimi path, `mimi_post_swipes`, checks whether the pointer is inside the target display's bounds. If it is, nothing changes from before. If not, it warps the pointer to the display's centre, waits 30 ms as mimi does, posts the swipes, waits 30 ms after the last one as well so the Dock reads them before the pointer moves, warps the pointer back, and calls `CGAssociateMouseAndMouseCursorPosition(true)` to end the short freeze of real mouse movement a warp causes. Restoring is dinky's own choice; none of the sources do it. It does not copy the menu-bar and click follow-up from mimi and yabai, because dinky switches the focused display, which should already own the menu bar; step 6 below checks that. The Tuna, bridged, keys and number paths are unchanged. In the VM (one display, pointer always on it) `switch 2` and `switch 1` with `--path mimi` still land, and `--times 10` landed 10 of 10, median 110 ms, just after a VM reboot.

Untested alternative: set the swipe events' location (`CGEventSetLocation`) to the target display instead of moving the pointer. No source does this, and it only helps if the Dock reads the event location rather than the WindowServer cursor. Worth one try on two displays if the warp flicker bothers.

**Test procedure for the host with two displays**

Setup: two displays attached, "Displays have separate Spaces" on (the default), at least 2 Spaces on each display, `mru-spaces` false, `swift build` done. Run everything from the repo with `.build/debug/dinky`. `dinky switch` always acts on the main display (the one with the menu bar in System Settings > Displays, Switch.swift:47), so the display under test is chosen by moving the pointer, not by a flag. `sleep 3;` gives you time to move the pointer after pressing Return.

1. `.build/debug/dinky ls`. Expect two displays, one marked `(main)`, each with a `*` on its current Space. Note both current Spaces.
2. Pointer on the main display: `.build/debug/dinky switch 2 --path mimi`. Expect `mimi 1 -> 2 landed` in roughly 40 to 100 ms, the main display on Space 2, the other display unchanged, and the pointer not moving (no warp). Then `switch 1 --path mimi` to go back.
3. The case this ticket is about: `sleep 3; .build/debug/dinky switch 2 --path mimi`, and during the sleep put the pointer on the secondary display and leave it still. Expect `landed` in roughly 100 to 170 ms (the warp adds two 30 ms waits), the **main** display on Space 2, the secondary display's Space unchanged, and the pointer back where you left it after at most a brief flicker to the main display's centre. `ls` should agree on both displays.
4. Same with the pointer on the secondary display: `sleep 3; .build/debug/dinky switch 1 --path mimi --times 10`. Expect `10 landed, 0 timed out`, the secondary display never changing, and the pointer ending where you left it.
5. Mouse during the warp: `sleep 3; .build/debug/dinky switch 2 --path mimi`, and keep moving the mouse on the secondary display through the switch. Expect the switch to land on the main display, and the pointer not to stick or freeze after it jumps back.
6. Menu bar and focus: after step 3, note which display shows the active (non-dimmed) menu bar and which window has keyboard focus. Expect both unchanged from before the switch. If the menu bar moved to the main display, record it: mimi and yabai set it explicitly after a warp, and dinky may need to do the same or deliberately undo it.
7. The other direction: in System Settings > Displays > Arrange, drag the menu bar to the other display so it becomes main; `ls` shows `(main)` moved. Repeat steps 2 and 3 with the roles swapped (the pointer now sits on the former main display in step 3). Expect the same results. Move the menu bar back afterwards.
8. If step 3 switches the secondary display instead, or times out: the warp did not reach the Dock in time. Record the output. The next things to try are a longer wait after the warp in `mimi_post_swipes`, then the `CGEventSetLocation` alternative above.

Pass means steps 3, 4 and 7 behave as described. Then close din-8j6i.

## Space creation spike: works

Run on 25 September 2026 in the same VM (macOS 27.0 26A5416b, SIP off, one 1024x768 display, 3 Spaces at the start). Ticket din-19v3.

**Result: dinky can create a user Space on a display with `SLSBridgedSpaceCreateOperation`, through SkyLight's synchronous bridged dispatcher. Mission Control shows it, windows move to it, the swipe switches to it, and it survives `killall Dock`.** Nothing is injected into the Dock, so SIP should not matter, but the host has not been tried.

### What the runtime says

A probe that walks `objc_copyClassList` for `SLSBridged*` gives the same answer on the host (26A428) and in the VM (26A5416b):

```
SLSBridgedSpaceCreateOperation : SLSSynchronousBridgedWindowManagementOperation
  - initWithOptions:values:   @28@0:8I16@20     (uint32 options, NSDictionary values)
  - makeResultWithSpaceID:    @24@0:8Q16
  - invokeFallback            @16@0:8
  @ options TI,R   @ values T@"NSDictionary",R,C
SLSBridgedWindowManagementOperationSpaceIDResult
  - spaceID Q16@0:8
SLSBridgedSpaceDestroyOperation : SLSAsynchronousBridgedWindowManagementOperation
  - initWithSpaceID: @24@0:8Q16
```

It is a *synchronous* operation, so the asynchronous dispatcher from move.m does not fit. SkyLight has a synchronous twin, also non-exported: `__ZL54_SLSPerformSynchronousBridgedWindowManagementOperationP46SLSSynchronousBridgedWindowManagementOperation`. It returns the result object. Disassembly shows:

- The dispatcher and `-performWithWMBridgeDelegate` are the same code: both hand the operation to `SLSWMBridgeDelegate()`. In a client process that is `SLSWindowManagementFallbackBridge`, which calls `-invokeFallback`. For this class that means `SLSWindowServerClientSpaceCreate(…, options, values)`, a MIG call to WindowServer. The Dock is not involved.
- The exported `SLSSpaceCreate(cid, options, values)` builds the same operation when `SLSWindowManagementClientOperationsEnabled()` is true, and otherwise calls `SLSWindowServerClientSpaceCreate` directly.

No option or dictionary key is documented. The values follow bobrwm (below): `type` = 0 (user) and `Display Identifier` = the display UUID. `options` = 0.

### What other window managers do

- **yabai** (`space_manager_add_space`): only through its scripting addition. It injects into the Dock and calls the Dock's own `addSpace` on a new `ManagedSpace`. That needs SIP off, so it is not an option for dinky.
- **bobrwm** (`skylight.zig createNativeSpace`): exactly this path. It calls `[[SLSBridgedSpaceCreateOperation alloc] initWithOptions:0 values:@{type: 0, "Display Identifier": uuid}]`, then `performWithWMBridgeDelegate`, and reads `spaceID` from the result. It then polls `SLSCopyManagedDisplaySpaces` until the count grows. It also uses `SLSBridgedSpaceDestroyOperation initWithSpaceID:` to remove Spaces.

### Calls and results on 26A5416b

| Call | Process | Result |
|---|---|---|
| `dinky spaces create` (bridged op through the sync dispatcher) | dinky (links AppKit) | `SpaceIDResult` with spaceID 23. In `SLSCopyManagedDisplaySpaces` immediately, type 0 |
| same, `--display <uuid> --restart-dock` | dinky | spaceID 32. Still listed after `killall Dock` |
| bridged op via `-performWithWMBridgeDelegate` | bare Foundation probe | result **nil**, nothing created |
| same, with `SLSCopyManagedDisplaySpaces` called first | bare Foundation probe | nil |
| same | probe linking AppKit (`NSApplicationLoad()` or just touching `NSScreen`) | spaceID 44 / 45, created |
| exported `SLSSpaceCreate(cid, 0, values)` | bare probe, and AppKit probe | returns 0, nothing created |
| `SLSBridgedSpaceDestroyOperation` via `-performWithWMBridgeDelegate`, and exported `SLSSpaceDestroy` | bare probe, on Spaces 23 and 32 | nothing removed (return 0) |

So the working form is the bridged op, sent from a process with AppKit loaded. dinky already links AppKit. Removing a Space from outside did not work, not even with the original creator gone. That is fine: removal is out of v1. The test Spaces were removed with Mission Control's own close button.

### Mission Control and the Dock

Screenshots were taken in the VM with Control-Up and `screencapture`, and checked by eye. Copies are in the spike agent's scratchpad; they are not committed.

- Before: Desktop 1 to 3.
- After `spaces create`: **Desktop 4** appears at the end of the strip, with no Dock restart and no delay.
- `dinky move 47 4` moved a TextEdit window there in 15 ms. `dinky switch 4 --path mimi` switched to it in 437 ms. The screen showed an empty desktop with TextEdit, and the menu bar number read 4.
- **`killall Dock` was run twice** in the VM. After it, `spaces ls` still showed Space 23, and Mission Control still showed Desktop 4 with the TextEdit thumbnail on it. Space 32 also survived its restart.

The first two test Spaces (23, 32) were removed and 3 Spaces were confirmed. After the AppKit probe runs, the VM had 5 Spaces (44 and 45 added). The same Mission Control cleanup was sent, but the VM stopped answering on the network during it (tart still reports it running), so the final count is unverified. Expect 3, or 5 if the clicks did not land. Either way it is at least 3.

### Recommendation

Use it. `dinky_create_space(displayUUID)` in `Sources/DinkyPrivate/spaces.m` is the real function. It returns the new Space ID, or 0 with the reason on stderr. The "ensure workspace count" feature (din-son6) can call it once per missing Space, then wait until `dinky_displays()` lists the new ID; it showed up on the first poll here. Open points:

- **Host with SIP on:** not tested, per the brief. Nothing on this path touches the Dock, and the call is a plain client-to-WindowServer MIG call, so SIP should not matter. Confirm on the host before relying on it; it is a one-line `dinky spaces create`.
- **Multi-display:** not tested, since the VM has one display. `--display <uuid>` goes into `Display Identifier`, which is the only way the target display is chosen.
- **The exported `SLSSpaceCreate` does not work** on this build. Do not replace the dispatcher lookup with it.
