# dinky

dinky is a tiling window manager for macOS that uses the native Spaces as its workspaces. It switches between Spaces in well under a tenth of a second, tiles the windows on each one, and draws a border around the focused window. It runs with System Integrity Protection left on.

It is not a compositor: macOS still draws every window, and dinky can only ask apps to move and resize. It has no scrolling or infinite-canvas layouts, no focus-follows-mouse and no animations.

dinky is not released yet. Parts of it are still being built; see [Status](#status).

## Requirements

- **macOS 27.** Only 27.0 has been tried. dinky relies on private system calls that change between releases (see [How switching works](#how-switching-works)).
- **Apple silicon** is assumed. Intel Macs have not been tried.
- **Xcode or the Swift 6 toolchain** and [`just`](https://github.com/casey/just) to build.
- **Accessibility permission.** dinky moves and resizes windows and listens for its key bindings through the Accessibility API. The first run asks for it.
- **The Cmd-Tab setting.** macOS has a setting, "When switching to an application, switch to a Space with open windows" (System Settings > Desktop & Dock > Mission Control). With it on, Cmd-Tab or a Dock click to an app on another Space plays the slow slide animation. With it off, macOS only activates the app, and dinky switches to the app's Space itself, fast. The first run offers to turn it off. Turning it off restarts the Dock. You can say no; everything else works.

## Install from source

```sh
git clone <repo> dinky && cd dinky
IDENTITY="Apple Development: Your Name (TEAMID)" just bundle
open build/dinky.app      # or: just run
```

`just bundle` runs `scripts/bundle.sh`, which builds a release binary and puts the signed app at `build/dinky.app`. `just bundle --debug` builds a debug one.

The script signs with the identity in `IDENTITY`, which defaults to the author's certificate, so set it to one of yours (`security find-identity -p codesigning` lists them). A stable identity matters: macOS ties the Accessibility grant to the signature, and with ad-hoc signing (`IDENTITY=-`) every rebuild loses the grant. `VERSION` and `BUILD` set the bundle version.

Move `build/dinky.app` to `/Applications` if you like. dinky is a menu bar app with no Dock icon.

### First run

1. dinky writes the default config to `~/.config/dinky/dinky.toml` if there is none.
2. A window asks for Accessibility. "Open Accessibility Settings" takes you to Privacy & Security > Accessibility; turn dinky on there. The window moves on by itself once it is allowed.
3. Once, dinky offers to turn off "switch to a Space with open windows" (above). "Turn It Off" runs `defaults write com.apple.dock workspaces-auto-swoosh -bool false` and restarts the Dock. "Leave It" keeps the setting and does not ask again.
4. The menu bar shows the current Space number. Its menu switches workspaces, moves the focused window, toggles dinky on and off, reloads the config and quits.

The shipped config has `start-at-login = true`, so dinky registers itself as a login item.

### Uninstall

Quit dinky from its menu, delete the app and `~/.config/dinky`, and remove it from Accessibility and Login Items in System Settings. To get the Cmd-Tab slide back:

```sh
defaults write com.apple.dock workspaces-auto-swoosh -bool true && killall Dock
```

## How switching works

macOS has no public way to switch Spaces quickly. The keyboard shortcuts (Control-Arrow) play the full slide animation, about half a second each time. A trackpad swipe does the same, but the Dock, which owns Spaces, finishes the gesture instantly when the swipe is fast enough. So dinky pretends to be a trackpad: it posts a synthetic Dock swipe gesture, with the private event fields and serialized touch payload a real one carries, and an absurd velocity. The Dock jumps straight to the target Space. In testing that took 41 to 99 ms, median 66 ms, against about 560 ms for Control-Arrow. The technique comes from mimi; Tuna and yabai use variants of it. The Dock swipes the display under the pointer, so to switch another display dinky briefly moves the pointer there and back.

Moving a window to another Space goes through a private SkyLight (WindowServer) operation, which took 3 to 14 ms in testing and needs no Dock injection. Creating missing Spaces uses a similar operation. Focus and tiling use the public Accessibility API.

None of this touches the Dock's process or needs SIP off, which is what separates dinky from yabai's full feature set. The cost is that the swipe event format and the SkyLight operations are private and undocumented. They were found by reading other projects' source and SkyLight's runtime, and a macOS update can change or remove them without notice. One such change has already happened: the simpler swipe form Tuna uses is ignored by the Dock on macOS 27, as mimi notes. Expect dinky to need fixes after macOS updates, especially major ones.

## Config

The config lives at `~/.config/dinky/dinky.toml`. It is TOML, with key names taken from [AeroSpace](https://github.com/nikitabobko/AeroSpace) where dinky has the same feature, so AeroSpace binding tables mostly carry over.

- If the file is missing, dinky writes the default config below.
- With `auto-reload-config` on, dinky reloads the file when it changes. `dinky reload-config` does it by hand.
- A config with an error does not load: dinky keeps the previous one and shows the error at the top of its menu bar menu. Unknown keys are errors, so typos do not pass silently.
- Every key is optional. A key you leave out takes the default in the table below, **not** the value from the shipped file. In particular, a config without `[mode.main.binding]` has no key bindings, and one without `start-at-login` does not start at login.

### Top level

| Key | Default | Meaning |
|---|---|---|
| `config-version` | `1` | Config format version. Only `1` is accepted. |
| `start-at-login` | `false` | Register dinky as a login item. The shipped file sets `true`. |
| `auto-reload-config` | `true` | Reload the config when the file changes. |
| `workspaces` | `5` | Spaces per display, at least 1. dinky creates missing Spaces and never removes any. |

### `[layout]`

| Key | Default | Meaning |
|---|---|---|
| `default` | `'tiles'` | Layout for new containers: `'tiles'` or `'accordion'`. |
| `accordion-padding` | `30` | Points by which neighbouring windows peek out in an accordion. |

### `[gaps]`

| Key | Default | Meaning |
|---|---|---|
| `inner` | `8` | Points between tiled windows. |
| `outer` | `8` on every side | Points between tiled windows and the screen edge. Either one number, `outer = 8`, or a table `outer = { top = 8, bottom = 8, left = 8, right = 8 }`; sides left out of the table are 0. |

### `[borders]`

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `true` | Draw a border around windows. |
| `width` | `4` | Border width in points. May be fractional. |
| `active-color` | `'#e1e3e4'` | Colour of the focused window's border, `'#rrggbb'` or `'#rrggbbaa'`. |
| `inactive-color` | `'#494d64'` | Colour of other windows' borders, same format. |
| `style` | `'round'` | Corner style: `'round'` or `'square'`. |

### `[switching]`

| Key | Default | Meaning |
|---|---|---|
| `follow-app-activation` | `true` | When Cmd-Tab or a Dock click activates an app on another Space, switch there with the fast switch. Works when the macOS "switch to a Space with open windows" setting is off. |

### `[[on-window-detected]]`

Rules for new windows, one table per rule. When a new window matches every condition under `if`, dinky runs the rule's commands. Rules are checked in order, and the first match ends the search unless it sets `check-further-callbacks`.

Dialogs, sheets, panels and windows that cannot be resized float without a rule. Floating windows keep their own position and size.

| Key | Default | Meaning |
|---|---|---|
| `if.app-id` | none | The app's bundle ID, e.g. `'com.apple.Safari'`. |
| `if.app-name-regex-substring` | none | Case-insensitive regex found anywhere in the app's name. |
| `if.window-title-regex-substring` | none | Case-insensitive regex found anywhere in the window title. |
| `if.window-kind` | none | `'normal'`, `'dialog'`, `'sheet'` or `'panel'`. dinky's own; not in AeroSpace. |
| `check-further-callbacks` | `false` | Keep checking later rules after this one matches. |
| `run` | required | A command or a list of commands, e.g. `'layout floating'`. |

```toml
[[on-window-detected]]
if.app-name-regex-substring = 'finder'
run = 'layout floating'
```

### `[mode.<name>.binding]`

Key bindings, grouped in modes. dinky starts in `main`; the `mode <name>` command switches. Each entry maps a key combination to a command or a list of commands, run in order:

```toml
[mode.main.binding]
alt-1 = 'workspace 1'
alt-shift-semicolon = 'mode service'

[mode.service.binding]
esc = ['reload-config', 'mode main']
```

A bound key is swallowed; other keys pass through to the app. Binding the same combination twice in a mode is an error.

**Key syntax.** Zero or more modifiers and one key, joined by `-`, as in AeroSpace: `alt-shift-h`, `ctrl-left`, `f5`.

- Modifiers: `alt` (Option), `ctrl`, `cmd`, `shift`, in any order.
- Letters `a` to `z` and digits `0` to `9`.
- `f1` to `f20`.
- `minus`, `equal`, `leftSquareBracket`, `rightSquareBracket`, `backslash`, `semicolon`, `quote`, `comma`, `period`, `slash`, `backtick`, `sectionSign`.
- `space`, `enter`, `esc`, `backspace`, `tab`, `forwardDelete`, `left`, `down`, `up`, `right`, `pageUp`, `pageDown`, `home`, `end`.
- Keypad: `keypad0` to `keypad9`, `keypadClear`, `keypadDecimalMark`, `keypadDivide`, `keypadEnter`, `keypadEqual`, `keypadMinus`, `keypadMultiply`, `keypadPlus`.

Key names refer to positions on a US (qwerty) layout. Note that the default `alt-` bindings take over Option-letter combinations you might use to type special characters.

### The default config

This is what dinky writes on first run:

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
alt-1 = 'workspace 1'
alt-2 = 'workspace 2'
alt-3 = 'workspace 3'
alt-4 = 'workspace 4'
alt-5 = 'workspace 5'
alt-6 = 'workspace 6'
alt-7 = 'workspace 7'
alt-8 = 'workspace 8'
alt-9 = 'workspace 9'
alt-shift-1 = 'move-window-to-workspace 1'
alt-shift-2 = 'move-window-to-workspace 2'
alt-shift-3 = 'move-window-to-workspace 3'
alt-shift-4 = 'move-window-to-workspace 4'
alt-shift-5 = 'move-window-to-workspace 5'
alt-shift-6 = 'move-window-to-workspace 6'
alt-shift-7 = 'move-window-to-workspace 7'
alt-shift-8 = 'move-window-to-workspace 8'
alt-shift-9 = 'move-window-to-workspace 9'
alt-tab = 'workspace-back-and-forth'
alt-h = 'focus left'
alt-j = 'focus down'
alt-k = 'focus up'
alt-l = 'focus right'
alt-shift-h = 'move left'
alt-shift-j = 'move down'
alt-shift-k = 'move up'
alt-shift-l = 'move right'
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
alt-shift-h = ['join-with left', 'mode main']
alt-shift-j = ['join-with down', 'mode main']
alt-shift-k = ['join-with up', 'mode main']
alt-shift-l = ['join-with right', 'mode main']
```

With 5 workspaces, `alt-6` to `alt-9` do nothing until you raise `workspaces`.

## Commands

Bindings, the command line and the menu bar share one set of commands. `dinky help` prints this list.

| Command | What it does |
|---|---|
| `workspace <number\|prev\|next>` | Switch the focused display to a workspace (a native Space), numbered from 1. `prev` and `next` do not wrap. |
| `workspace-back-and-forth` | Switch to the workspace that was focused before the current one. |
| `move-window-to-workspace <number\|prev\|next> [--follow]` | Move the focused window to a workspace. With `--follow`, switch there too. |
| `move-window-to-display <next\|prev> [--follow]` | Move the focused window to the next or previous display. With `--follow`, focus it there. |
| `focus <left\|down\|up\|right>` | Focus the nearest window in a direction. |
| `move <left\|down\|up\|right>` | Move the focused window in a direction within the layout tree. |
| `join-with <left\|down\|up\|right>` | Put the focused window and its neighbour in a new container. |
| `resize <smart\|width\|height> <+N\|-N>` | Grow or shrink the focused window by N points. |
| `layout <tiles\|accordion\|floating\|tiling>...` | Set the layout of the focused window's container, or float or tile the window. With several, apply the first that is not current, so `layout floating tiling` toggles. |
| `fullscreen` | Toggle the focused window filling the workspace. The tree is kept. This is not macOS full screen. |
| `flatten-workspace-tree` | Put every window on the workspace back into one flat container. |
| `retile` | Re-read every window and re-apply the layout of every workspace on screen. |
| `mode <name>` | Switch to a binding mode from the config, such as `main` or `service`. |
| `reload-config` | Reload `~/.config/dinky/dinky.toml`. On an error the previous config stays. |
| `enable <on\|off\|toggle>` | Turn dinky's key bindings and app-activation following on or off. |
| `list-workspaces [flags]` | Print workspace numbers. See [Scripting and SketchyBar](#scripting-and-sketchybar). |
| `list-windows [flags]` | Print windows as `id \| app \| title`. See below. |
| `list-monitors [flags]` | Print displays as `number \| name`. `list-displays` is the same. |
| `exec-and-forget <shell command>` | Run the rest of the line with `/bin/sh -c` without waiting. Its output goes to dinky's log. |

Workspaces are counted per display, and workspace commands act on the display that has focus. A full-screen app's Space is not a numbered workspace; workspace commands there answer "not on a numbered workspace".

## Command line and socket

The app binary is also the command line tool. Link it onto your `PATH`:

```sh
ln -s /Applications/dinky.app/Contents/MacOS/dinky /usr/local/bin/dinky
```

Then `dinky <command>` runs any command above in the running app, for example `dinky workspace 3` or `dinky list-windows`. The CLI checks the command first and prints the expected syntax if it does not parse. It exits 0 on success and 1 on an error or when the app is not running. Run from a shell with no arguments, the binary prints usage instead of starting the app; `dinky app` starts the app in the foreground, which is handy for seeing its log.

The CLI talks to the app over a unix socket at `$TMPDIR/dinky.sock` (your per-user temp directory; `dinky help` prints the full path). The protocol is one command per connection: write the command line ending in a newline, and read the answer, a first line of `ok` or `error` followed by the reply text. So scripts can skip the CLI:

```sh
printf 'workspace 2\n' | nc -U "$TMPDIR/dinky.sock"
```

A few subcommands are for the command line only: `dinky app` (above), `dinky recover` restores the windows a crashed session left tiled, and `dinky debug events` or `dinky debug windows` print the live window event stream or the current windows without the app, which is useful in a bug report.

## Scripting and SketchyBar

The queries and callbacks follow [AeroSpace](https://nikitabobko.github.io/AeroSpace/commands)'s names, flags and output, so bar scripts written for AeroSpace mostly work by changing `aerospace` to `dinky`: `aerospace list-windows --workspace 3` becomes `dinky list-windows --workspace 3` with the same output. The difference is that dinky's workspaces are numbers per display, so with two displays the numbers repeat.

**Queries.** Each prints one line per item. Without a display flag they cover the focused display.

| Query | Flags | Default output |
|---|---|---|
| `list-workspaces` | `--all` (every display), `--focused` (the focused workspace), `--monitor <focused\|all\|n>...`, `--visible [no]`, `--empty [no]`, `--format` | `%{workspace}` |
| `list-windows` | `--all`, `--focused` (the focused window), `--monitor <focused\|all\|n>...`, `--workspace <focused\|visible\|n>...` (repeatable), `--app-bundle-id <id>`, `--format` | `%{window-id}%{right-padding} \| %{app-name}%{right-padding} \| %{window-title}` |
| `list-monitors` | `--focused [no]`, `--format` | `%{monitor-id}%{right-padding} \| %{monitor-name}` |

`--format` takes a string with `%{variable}`s; quote it. `%{right-padding}` pads to line up columns, `%{newline}` and `%{tab}` insert those characters.

- Workspaces: `%{workspace}` (the number), `%{workspace-is-focused}`, `%{workspace-is-visible}`, `%{monitor-id}` (1-based display number), `%{monitor-name}`, `%{monitor-is-main}`.
- Windows: `%{window-id}`, `%{window-title}`, `%{window-layout}` (`h_tiles`, `v_tiles`, `h_accordion`, `v_accordion`, `floating` or `fullscreen`), `%{window-is-floating}`, `%{window-is-fullscreen}`, `%{app-name}`, `%{app-bundle-id}`, `%{app-pid}`, plus the workspace and monitor variables.
- Monitors: `%{monitor-id}`, `%{monitor-name}`, `%{monitor-is-main}`.

`dinky list-workspaces --all` prints every display's numbers, so `for sid in $(dinky list-workspaces --all)` repeats them on two displays; `--format '%{monitor-id}-%{workspace}'` tells them apart.

**Callbacks.** Top-level config keys, empty by default:

```toml
# A program and its arguments, run whenever a display's current workspace changes, by dinky or natively.
exec-on-workspace-change = ['/bin/bash', '-c',
    'sketchybar --trigger aerospace_workspace_change FOCUSED_WORKSPACE=$DINKY_FOCUSED_WORKSPACE'
]
# dinky commands, run when the focused window changes (debounced by 50 ms) and when the binding mode changes.
on-focus-changed = ['exec-and-forget sketchybar --trigger aerospace_mode_changed']
on-mode-changed = ['exec-and-forget sketchybar --trigger aerospace_mode_changed']
```

`exec-on-workspace-change` gets `DINKY_FOCUSED_WORKSPACE` (the new number, empty on a full-screen app's Space), `DINKY_PREV_WORKSPACE` and `DINKY_MONITOR_ID` (the display that switched), and the first two again as `AEROSPACE_FOCUSED_WORKSPACE` and `AEROSPACE_PREV_WORKSPACE` so AeroSpace scripts keep working. Programs started by callbacks and `exec-and-forget` find Homebrew's `/opt/homebrew/bin` on `PATH`. Nothing fires while dinky starts up.

## Status

Every v1 command in `dinky help` is implemented and was verified in a macOS 27 VM. What has not yet been run anywhere is listed in the next section.

## Known limits and what is unverified

- **Tested in a VM on a beta, with SIP off.** The switching, moving, focus and tiling results come from a macOS 27.0 beta VM (build 26A5416b) with SIP disabled, which is how the VM images ship. The binary was built on a host running 27.0 (26A428) with SIP on, but the full tests have not been rerun there. Nothing dinky does should need SIP off, but that is not yet confirmed.
- **One display only.** Every test ran on a single display. Multiple displays, switching a display that does not have the pointer, moving windows between displays and creating Spaces on a second display are untested.
- **Pointer warp.** To switch a display the pointer is not on, dinky moves the pointer there for about 60 ms and back. You may see a flicker.
- **Space creation** worked in the VM, including after restarting the Dock, but is untested on a host with SIP on. dinky cannot remove Spaces; use Mission Control.
- **Cmd-Tab following** was measured at 60 to 80 ms with `open -a`. Apps with windows on several Spaces, apps with no windows, and the real Cmd-Tab switcher are not yet tested.
- **Apps refuse some sizes.** Safari enforces a minimum width and Terminal snaps to its character grid, so tiles can overlap or leave gaps. dinky cannot force a size.
- **Focus across Spaces.** macOS cannot focus a window on another Space, so dinky switches first.
- **Private APIs.** See [How switching works](#how-switching-works). A macOS update can break switching, moving or Space creation.

## Credits

dinky studies the approaches of these projects. Where code was adapted, the license is noted.

- [yabai](https://github.com/asmvik/yabai) (MIT): SkyLight function signatures, window filtering, focus and WindowServer event handling. dinky uses only yabai's SIP-on paths, not its scripting addition.
- [mimi](https://github.com/y3owk1n/mimi) (MIT): the augmented Dock swipe that makes switching fast, and the Mach-O symbol lookup for the bridged SkyLight operations.
- [AeroSpace](https://github.com/nikitabobko/AeroSpace) (MIT): config shape, key names and key syntax, the command vocabulary and the accordion layout.
- [JankyBorders](https://github.com/FelixKratz/JankyBorders) (GPL-3.0): studied only. dinky's borders and WindowServer notifications follow its approach but are written from scratch.
- [Tuna](https://tunaformac.com): an earlier synthetic Dock swipe, studied.
- [bobrwm](https://github.com/bobrwm/bobrwm) (MIT): studied for creating Spaces with the bridged SkyLight operation.

dinky itself has no license chosen yet.
