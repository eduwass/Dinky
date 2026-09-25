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
