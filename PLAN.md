# dinky v1: daily driver

A SIP-on tiling window manager for macOS built on native Spaces. The spike (RESULTS.md) proved the mechanics: mimi's augmented Dock swipe switches Spaces in about 70 ms, the bridged SkyLight operation moves windows between Spaces in about 4 ms, AX raise focuses, AX frame writes tile. This plan takes that to something usable every day on the author's machines.

Agreed 25 September 2026. Work is tracked with `tk` in `.tickets/`; `tk ready` lists what can start. The research archive is RESEARCH.md.

## Decisions

| Area | Decision |
|---|---|
| Workspaces | Native Spaces, numbered 1..N per display. Config says how many; dinky creates missing ones on start and never removes any. |
| Displays | Multi-display from the start. Each display has its own Spaces and its own layout trees. Bindings act on the focused display. Windows can be moved between displays. |
| New windows | Tiled automatically as they appear. Sheets, dialogs, utility panels and per-app rules float. |
| Layouts | Tiles with widest-axis insertion, stable split axes. Accordion as a container mode, AeroSpace style: children overlap, neighbours peek out by `accordion-padding`. |
| Floating | Toggle per window, per-app rules in config. Floating windows keep native placement. |
| Bindings | `alt` is the default modifier, AeroSpace vocabulary and key syntax. `ctrl-left/right` also bound to workspace prev/next. Modes supported. |
| Moving windows | `move-window-to-workspace N` stays put; `--follow` or a second binding follows. Same for displays. |
| Switching | mimi's augmented swipe on the target display. Cmd-Tab and Dock activations are followed with the same swipe, with the native "switch to a Space with open windows" setting off. Onboarding asks before changing that setting. |
| Borders | Built in, JankyBorders approach reimplemented (it is GPL). Every focused window gets a border, tiled or floating. |
| Gaps | Inner and outer, in config. |
| Extras in v1 | Fullscreen toggle (tile fills the Space, tree kept), workspace back-and-forth, resize smart +/-, swap and join-with. |
| Mouse | No focus-follows-mouse in v1. |
| Menu bar | Current Space number plus the action menu, as in the spike. |
| App | Signed bundle, launch at login, Accessibility onboarding, restore-on-quit. Direct build, no updater. |
| CLI | `dinky <command>` talks to the app over a unix socket. Bindings and CLI share one command vocabulary. |
| Config | `~/.config/dinky/dinky.toml`, parsed with TOMLDecoder, reloaded on change and by `reload-config`. |

## Config draft

```toml
config-version = 1
start-at-login = true
auto-reload-config = true
workspaces = 5                 # per display; dinky creates missing Spaces, never removes

[layout]
default = 'tiles'              # tiles | accordion
accordion-padding = 30

[gaps]
inner = 8
outer = { top = 8, bottom = 8, left = 8, right = 8 }

[borders]
enabled = true
width = 4
active-color = '#e1e3e4'
inactive-color = '#494d64'
style = 'round'                # round | square

[switching]
follow-app-activation = true   # Cmd-Tab and Dock clicks go through the fast switch

[[on-window-detected]]
if.app-id = 'com.apple.systempreferences'
run = 'layout floating'

[mode.main.binding]
ctrl-left = 'workspace prev'
ctrl-right = 'workspace next'
alt-1 = 'workspace 1'          # ... alt-9
alt-shift-1 = 'move-window-to-workspace 1'
alt-tab = 'workspace-back-and-forth'
alt-h = 'focus left'           # j k l
alt-shift-h = 'move left'      # j k l
alt-minus = 'resize smart -50'
alt-equal = 'resize smart +50'
alt-f = 'fullscreen'
alt-shift-f = 'layout floating tiling'
alt-comma = 'layout accordion'
alt-slash = 'layout tiles'
alt-shift-n = 'move-window-to-display next'
alt-shift-semicolon = 'mode service'

[mode.service.binding]
esc = ['reload-config', 'mode main']
r = ['flatten-workspace-tree', 'mode main']
alt-shift-h = ['join-with left', 'mode main']   # j k l
```

## Architecture

```text
dinky.app (menu bar, accessory)            dinky CLI ── unix socket ──┐
  Config (TOML, watched) ─► Hotkeys (event tap, modes) ─► Commands ◄──┘
  WindowServer events (SLSRegisterNotifyProc) ─► Window model, Display/Space model
  Layout engine (pure, one tree per Space) ─► Frame applier (AX, per-app coalescing, gaps)
  Borders (SLS windows ordered with the target) ◄── window model
  Spaces adapter: mimi swipe per display, bridged move, bridged create
```

One serialized coordinator owns state. WindowServer notifications replace polling. Private calls stay behind the existing Objective-C target with capability checks. The pure layout engine is tested without macOS.

## Epics, in build order

1. **Foundation.** App bundle and onboarding, config, command dispatcher, CLI socket, and the WindowServer event stream that everything else consumes.
2. **Spaces and displays.** Two spikes first: creating Spaces with the bridged operation, and fast switching on a display that does not have the cursor. Then the display/Space model, ensuring the workspace count, workspace commands, moving windows, activation following.
3. **Layout.** Tree model with pure tests, frame applier, automatic tiling on events, floating rules, directional commands, accordion, resize, fullscreen, join-with, native tabs and dialogs.
4. **Visuals.** Borders, then border polish.
5. **Hotkeys.** Engine with modes and chained commands, default config.
6. **Release.** Restore-on-quit and crash recovery, menu bar wiring, host validation with SIP on, docs.

## Risks

- **Space creation** through `SLSBridgedSpaceCreateOperation` is untested. If it fails, v1 asks the user to create desktops in Mission Control and the "ensure count" feature waits.
- **Non-cursor display switching.** The Dock swipe acts on the display the gesture is attributed to. mimi and Tuna target the cursor's display. Needs a spike; the fallback is warping the cursor for the duration of the swipe.
- **Bridged set-current-Space** was unreliable in the spike and is not used.
- **WindowServer notifications** and border ordering are proven in JankyBorders on 26, not yet on 27.
- **Beta build and SIP off in the VM.** The spike ran on 26A5416b with SIP disabled. Host validation with SIP on is a release ticket, not an afterthought.

## Not in v1

Focus-follows-mouse, animation, named workspaces, removing Spaces, a tab-bar stack mode, scripting hooks, an updater, App Store.
