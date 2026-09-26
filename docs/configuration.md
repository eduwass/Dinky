---
layout: default
title: Configuration
description: dinky's TOML config, every key and its default, and the key syntax.
permalink: /configuration/
---

# Configuration

> **TL;DR:** Edit `~/.config/dinky/dinky.toml`; dinky reloads it on save.
> Keys follow AeroSpace's names. A key you leave out takes its built-in
> default, not the value from the shipped file.

The config lives at `~/.config/dinky/dinky.toml`. It is TOML, with key names taken from [AeroSpace](https://github.com/nikitabobko/AeroSpace) where dinky has the same feature, so AeroSpace binding tables mostly carry over.

- If the file is missing, dinky writes the default config below.
- With `auto-reload-config` on, dinky reloads the file when it changes. `dinky reload-config` does it by hand.
- A config with an error does not load: dinky keeps the previous one and shows the error at the top of its menu bar menu. Unknown keys are errors, so typos do not pass silently.
- `dinky doctor` checks a config beyond parsing: that every binding, rule and callback command is in the vocabulary, that `mode X` names a mode, that key names are known, and that a main mode exists. `dinky doctor --config <path>` checks another file.
- Every key is optional. A key you leave out takes the default in the table below, **not** the value from the shipped file. In particular, a config without `[mode.main.binding]` has no key bindings, and one without `start-at-login` does not start at login.

## Top level

| Key | Default | Meaning |
|---|---|---|
| `config-version` | `1` | Config format version. Only `1` is accepted. |
| `start-at-login` | `false` | Register dinky as a login item. The shipped file sets `true`. |
| `auto-reload-config` | `true` | Reload the config when the file changes. |
| `workspaces` | `5` | Spaces per display, at least 1. dinky creates missing Spaces and never removes any. |

The callback keys `exec-on-workspace-change`, `on-focus-changed`, `on-mode-changed` and `after-startup-command` are top-level too; they are described under [Scripting and SketchyBar](commands.md#scripting-and-sketchybar).

## `[layout]`

| Key | Default | Meaning |
|---|---|---|
| `default` | `'tiles'` | Layout for new containers: `'tiles'` or `'accordion'`. |
| `accordion-padding` | `30` | Points by which neighbouring windows peek out in an accordion. |
| `accordion-orientation` | `'auto'` | What a container's orientation becomes when it switches to accordion: `'auto'`, so it runs along its longer side (windows peek out at the top and bottom of a tall column) and flips when resized past square, or `'keep'`, the orientation it had. An orientation chosen with `layout horizontal`, `vertical` or `auto` is always kept. |

## `[gaps]`

| Key | Default | Meaning |
|---|---|---|
| `inner` | `8` | Points between tiled windows. One value for both axes, or AeroSpace's `inner.horizontal` (between side-by-side windows) and `inner.vertical` (between stacked ones); an axis left out is 0. |
| `outer` | `8` on every side | Points between tiled windows and the screen edge. One value, `outer = 8`, or per side, `outer = { top = 8, bottom = 8, left = 8, right = 8 }` or `outer.top = 8`; sides left out are 0. |

Every gap value can instead be a per-display list, as in AeroSpace: `outer.top = [{ monitor."built-in" = 12 }, { monitor.main = 44 }, 8]`. Entries are tried in order and the first that matches the display wins; a bare number matches every display, so put it last as the fallback. With no match the gap is 0. Patterns are `main` (the main display in System Settings), `secondary` (the other one, when there are exactly two), or a case-insensitive substring of the display's name as `dinky list-monitors` prints it, such as `built-in` or `dell`. AeroSpace treats that last kind as a regex and also takes display numbers; dinky matches plain substrings only.

## `[borders]`

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `true` | Draw a border around windows. |
| `width` | `4` | Border width in points. May be fractional. |
| `active-color` | `'#e1e3e4'` | Colour of the focused window's border: `'#rrggbb'`, `'#rrggbbaa'`, or JankyBorders' `'0xaarrggbb'` so a bordersrc colour can be pasted in. |
| `inactive-color` | `'#494d64'` | Colour of other windows' borders, same format. |
| `style` | `'round'` | Corner style: `'round'` or `'square'`. |
| `order` | `'below'` | `'below'` draws the border directly below the window. `'above'` draws it above, as a ring that never covers the window's content or takes clicks. |
| `exclude-apps` | `[]` | Bundle IDs whose windows get no border. |
| `only-apps` | `[]` | When not empty, only these bundle IDs' windows get a border. |

## `[switching]`

| Key | Default | Meaning |
|---|---|---|
| `follow-app-activation` | `true` | When Cmd-Tab or a Dock click activates an app on another Space, switch there with the fast switch. Works when the macOS "switch to a Space with open windows" setting is off. |

## `[focus-follows-mouse]`

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `false` | Focus the window under the pointer once the pointer rests on it. Only windows dinky manages take focus; panels, menus, the menu bar, the Dock and the desktop never do. Nothing happens while a mouse button is down, while a menu is open, or for 300 ms after a Space change or a config reload, and windows that move under a still pointer never take focus. |
| `delay-ms` | `100` | How long the pointer must rest on a window before it takes focus. `0` focuses as soon as the pointer stops. |
| `accordion` | `true` | Whether resting on the peeking edge of an accordion child focuses it. With `false`, only an accordion's front window takes focus from hover. |

## `[[on-window-detected]]`

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

## `[mode.<name>.binding]`

Key bindings, grouped in modes. dinky starts in `main`; the `mode <name>` command switches. Each entry maps a key combination to a command or a list of commands, run in order:

```toml
[mode.main.binding]
alt-1 = 'workspace 1'
alt-shift-semicolon = 'mode service'

[mode.service.binding]
esc = ['reload-config', 'mode main']
```

A bound key is swallowed; other keys pass through to the app. Binding the same combination twice in a mode is an error.

## Key syntax

Zero or more modifiers and one key, joined by `-`, as in AeroSpace: `alt-shift-h`, `ctrl-left`, `f5`.

- Modifiers: `alt` (Option), `ctrl`, `cmd`, `shift`, in any order.
- Letters `a` to `z` and digits `0` to `9`.
- `f1` to `f20`.
- `minus`, `equal`, `leftSquareBracket`, `rightSquareBracket`, `backslash`, `semicolon`, `quote`, `comma`, `period`, `slash`, `backtick`, `sectionSign`.
- `space`, `enter`, `esc`, `backspace`, `tab`, `forwardDelete`, `left`, `down`, `up`, `right`, `pageUp`, `pageDown`, `home`, `end`.
- Keypad: `keypad0` to `keypad9`, `keypadClear`, `keypadDecimalMark`, `keypadDivide`, `keypadEnter`, `keypadEqual`, `keypadMinus`, `keypadMultiply`, `keypadPlus`.

Key names refer to positions on a US (qwerty) layout. Note that the default `alt-` bindings take over Option-letter combinations you might use to type special characters.

## The default config

This is what dinky writes on first run:

```toml
config-version = 1
start-at-login = true
auto-reload-config = true
workspaces = 5                 # per display; dinky creates missing Spaces, never removes

[layout]
default = 'tiles'              # tiles | accordion
accordion-padding = 30
accordion-orientation = 'auto' # auto: a new accordion runs along its longer side | keep

[gaps]
inner = 8
outer = { top = 8, bottom = 8, left = 8, right = 8 }

[borders]
enabled = true
width = 4
active-color = '#e1e3e4'
inactive-color = '#494d64'
style = 'round'                # round | square
order = 'below'                # below | above (a click-through ring over the window)
exclude-apps = []              # bundle IDs that get no border
only-apps = []                 # when set, only these bundle IDs get borders

[switching]
follow-app-activation = true   # Cmd-Tab and Dock clicks go through the fast switch

[focus-follows-mouse]
enabled = false                # focus the window under the pointer once it rests there
delay-ms = 100
accordion = true               # false: hovering a peeking accordion edge does not focus it

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
