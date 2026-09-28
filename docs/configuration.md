---
layout: default
title: Configuration
description: dinky's TOML config, every key and its default, and the key syntax.
permalink: /configuration/
---

# Configuration

> **TL;DR:** Edit `~/.config/dinky/dinky.toml`; dinky reloads it on save.
> A key you leave out keeps the value in the shipped file below.

The config lives at `~/.config/dinky/dinky.toml`. It is TOML.

- If the file is missing, dinky writes the default config below.
- dinky reloads the file when it changes. `dinky reload-config` does it by hand.
- A config with an error does not load: dinky keeps the previous one and shows the error at the top of its menu bar menu. Unknown keys are errors, so typos do not pass silently.
- `dinky doctor` checks a config beyond parsing: that every binding, rule and hook command is in the vocabulary, that `mode X` names a mode, that key names are known, and that a main mode exists. `dinky doctor --config <path>` checks another file.
- Every key is optional. A key you leave out keeps the value in the shipped file, which is what the tables below list as the default. The exceptions are the rules and bindings: a config without `[mode.main]` has no key bindings, and one without `[[rules]]` has no rules.

## Editor completion

dinky publishes a [JSON Schema](schemas/dinky.json) for the config. The shipped file starts with this Taplo schema directive, which gives validation, documentation and completion in TOML editors that support it, such as VS Code with Even Better TOML or Zed:

```toml
#:schema https://mikker.github.io/Dinky/schemas/dinky.json
# ~/.config/dinky/dinky.toml. Saved changes take effect at once.
# A key you leave out keeps the value shown here.
# Every key and command: https://mikker.github.io/Dinky/configuration/

start-at-login = true
workspaces = 5                  # per display; dinky creates missing Spaces, never removes any
default-layout = 'tiles'        # tiles | accordion
follow-app-activation = true    # Cmd-Tab and Dock clicks switch Spaces the fast way

[accordion]
padding = 30                    # points the neighbours peek out by
orientation = 'auto'            # auto: run along the container's longer side | keep

[gaps]
inner = 8                       # or { horizontal = 8, vertical = 8 }
outer = 8                       # or { top = 8, bottom = 8, left = 8, right = 8 }

# Overrides for one display: main, secondary, or part of its name as `dinky list-displays` prints it.
# [display.main]
# gaps.outer.top = 44

[borders]
enabled = true
width = 4
active-color = '#e1e3e4'        # '#rrggbb' or '#rrggbbaa'
inactive-color = '#494d64'
style = 'round'                 # round | square
order = 'below'                 # below | above (a click-through ring over the window)
exclude-apps = []               # bundle IDs whose windows get no border

[focus-follows-mouse]
enabled = false
delay-ms = 100                  # how long the pointer rests on a window before it takes focus
accordion-edges = true          # resting on a peeking accordion edge focuses that window

# dinky commands run on events. exec-and-forget gets $DINKY_WORKSPACE, $DINKY_PREV_WORKSPACE, $DINKY_DISPLAY.
# [hooks]
# startup = ['exec-and-forget brew services restart sketchybar']
# workspace-changed = ['exec-and-forget sketchybar --trigger workspace_change']
# focus-changed = []
# mode-changed = []

# Every rule whose conditions all match a new window runs, in order.
[[rules]]
app-id = 'com.apple.systempreferences'   # also: app-name, title (regexes), kind (normal|dialog|sheet|panel)
run = 'layout floating'

[mode.main]
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

[mode.service]
esc = ['reload-config', 'mode main']
r = ['flatten-workspace-tree', 'mode main']
alt-shift-h = ['join-with left', 'mode main']
alt-shift-j = ['join-with down', 'mode main']
alt-shift-k = ['join-with up', 'mode main']
alt-shift-l = ['join-with right', 'mode main']

```

The schema knows every key, the key syntax and the command names. `dinky doctor` checks the rest: that each command's arguments parse and that `mode X` names a mode.

## Top level

| Key | Default | Meaning |
|---|---|---|
| `start-at-login` | `true` | Register dinky as a login item. |
| `workspaces` | `5` | Spaces per display, at least 1. dinky creates missing Spaces and never removes any. A `[display.<pattern>]` table can set its own. |
| `default-layout` | `'tiles'` | Layout for new containers: `'tiles'` or `'accordion'`. |
| `follow-app-activation` | `true` | When Cmd-Tab or a Dock click activates an app on another Space, switch there with the fast switch. Works when the macOS "switch to a Space with open windows" setting is off. |

## `[accordion]`

| Key | Default | Meaning |
|---|---|---|
| `padding` | `30` | Points by which neighbouring windows peek out in an accordion. |
| `orientation` | `'auto'` | What a container's orientation becomes when it switches to accordion: `'auto'`, so it runs along its longer side (windows peek out at the top and bottom of a tall column) and flips when resized past square, or `'keep'`, the orientation it had. An orientation chosen with `layout horizontal`, `vertical` or `auto` is always kept. |

## `[gaps]`

| Key | Default | Meaning |
|---|---|---|
| `inner` | `8` | Points between tiled windows. One value for both axes, or `inner = { horizontal = 8, vertical = 6 }` (between side-by-side windows, and between stacked ones). |
| `outer` | `8` | Points between tiled windows and the screen edge. One value, or per side: `outer = { top = 44, bottom = 8, left = 8, right = 8 }` or `outer.top = 44`. |

A side or axis left out keeps its default, like every other key.

## `[display.<pattern>]`

Settings for one display. The pattern is `main` (the main display in System Settings), `secondary` (the other one, when there are exactly two), or a case-insensitive part of the display's name as `dinky list-displays` prints it, such as `built-in` or `dell`. Quote a pattern with spaces: `[display."LG UltraFine"]`.

A display table takes `gaps`, written as above, and `workspaces`, the number of Spaces on that display in place of the general count. A display table changes only what it sets; when several match one display, name patterns win over `main` and `secondary`, and a longer name pattern wins over a shorter one.

```toml
[gaps]
outer = 8

[display.main]          # the display with the bar
gaps.outer.top = 44

[display.built-in]
gaps.outer.top = 10
gaps.inner = 6

[display.secondary]     # one workspace on the second display
workspaces = 1
```

## `[borders]`

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `true` | Draw a border around windows. |
| `width` | `4` | Border width in points. May be fractional. |
| `active-color` | `'#e1e3e4'` | Colour of the focused window's border: `'#rrggbb'` or `'#rrggbbaa'`. |
| `inactive-color` | `'#494d64'` | Colour of other windows' borders, same format. |
| `style` | `'round'` | Corner style: `'round'` or `'square'`. |
| `order` | `'below'` | `'below'` draws the border directly below the window. `'above'` draws it above, as a ring that never covers the window's content or takes clicks. |
| `exclude-apps` | `[]` | Bundle IDs whose windows get no border. |

## `[focus-follows-mouse]`

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `false` | Focus the window under the pointer once the pointer rests on it. Only windows dinky manages take focus; panels, menus, the menu bar, the Dock and the desktop never do. Nothing happens while a mouse button is down, while a menu is open, or for 300 ms after a Space change or a config reload, and windows that move under a still pointer never take focus. |
| `delay-ms` | `100` | How long the pointer must rest on a window before it takes focus. `0` focuses as soon as the pointer stops. |
| `accordion-edges` | `true` | Whether resting on the peeking edge of an accordion child focuses it. With `false`, only an accordion's front window takes focus from hover. |

## `[hooks]`

dinky commands run on events. Each is a command or a list of commands, empty by default. Shell goes through `exec-and-forget`; see [Scripting and SketchyBar](commands.md#scripting-and-sketchybar) for the environment it gets.

| Key | Runs |
|---|---|
| `startup` | Once, when dinky starts, after it has read the windows and displays. |
| `workspace-changed` | Whenever a display's current workspace changes, by dinky or natively. |
| `focus-changed` | When the focused window changes, debounced by 50 ms. |
| `mode-changed` | When the binding mode changes. |

```toml
[hooks]
startup = ['exec-and-forget brew services restart sketchybar']
workspace-changed = ['exec-and-forget sketchybar --trigger workspace_change']
```

## `[[rules]]`

Rules for new windows, one table per rule. When a new window matches every condition a rule sets, dinky runs the rule's commands. Every matching rule runs, in file order; for `layout floating` and `layout tiling` the last one wins.

Dialogs, sheets, panels and windows that cannot be resized float without a rule. Floating windows keep their own position and size.

| Key | Default | Meaning |
|---|---|---|
| `app-id` | none | The app's bundle ID, e.g. `'com.apple.Safari'`. |
| `app-name` | none | Case-insensitive regex found anywhere in the app's name. |
| `title` | none | Case-insensitive regex found anywhere in the window title. |
| `kind` | none | `'normal'`, `'dialog'`, `'sheet'` or `'panel'`. |
| `run` | required | A command or a list of commands, e.g. `'layout floating'`. |

```toml
[[rules]]
app-name = 'finder'
run = 'layout floating'

[[rules]]
app-id = 'com.apple.Music'
run = ['layout floating', 'move-window-to-workspace 5']
```

## `[mode.<name>]`

Key bindings, grouped in modes. dinky starts in `main`; the `mode <name>` command switches. Each entry maps a key combination to a command or a list of commands, run in order:

```toml
[mode.main]
alt-1 = 'workspace 1'
alt-shift-semicolon = 'mode service'

[mode.service]
esc = ['reload-config', 'mode main']
```

A bound key is swallowed; other keys pass through to the app. Binding the same combination twice in a mode is an error.

## Key syntax

Zero or more modifiers and one key, joined by `-`: `alt-shift-h`, `ctrl-left`, `alt-page-up`, `f5`.

- Modifiers: `alt` (Option), `ctrl`, `cmd`, `shift`, in any order.
- Letters `a` to `z` and digits `0` to `9`.
- `f1` to `f20`.
- `minus`, `equal`, `left-bracket`, `right-bracket`, `backslash`, `semicolon`, `quote`, `comma`, `period`, `slash`, `backtick`, `section`.
- `space`, `enter`, `esc`, `backspace`, `tab`, `forward-delete`, `left`, `down`, `up`, `right`, `page-up`, `page-down`, `home`, `end`.
- Keypad: `keypad-0` to `keypad-9`, `keypad-clear`, `keypad-decimal`, `keypad-divide`, `keypad-enter`, `keypad-equal`, `keypad-minus`, `keypad-multiply`, `keypad-plus`.

Key names refer to positions on a US (qwerty) layout. Note that the default `alt-` bindings take over Option-letter combinations you might use to type special characters.

## The default config

This is what dinky writes on first run:

```toml
# ~/.config/dinky/dinky.toml. Saved changes take effect at once.
# A key you leave out keeps the value shown here.

start-at-login = true
workspaces = 5                  # per display; dinky creates missing Spaces, never removes any
default-layout = 'tiles'        # tiles | accordion
follow-app-activation = true    # Cmd-Tab and Dock clicks switch Spaces the fast way

[accordion]
padding = 30                    # points the neighbours peek out by
orientation = 'auto'            # auto: run along the container's longer side | keep

[gaps]
inner = 8                       # or { horizontal = 8, vertical = 8 }
outer = 8                       # or { top = 8, bottom = 8, left = 8, right = 8 }

# Overrides for one display: main, secondary, or part of its name as `dinky list-displays` prints it.
# [display.main]
# gaps.outer.top = 44

[borders]
enabled = true
width = 4
active-color = '#e1e3e4'        # '#rrggbb' or '#rrggbbaa'
inactive-color = '#494d64'
style = 'round'                 # round | square
order = 'below'                 # below | above (a click-through ring over the window)
exclude-apps = []               # bundle IDs whose windows get no border

[focus-follows-mouse]
enabled = false
delay-ms = 100                  # how long the pointer rests on a window before it takes focus
accordion-edges = true          # resting on a peeking accordion edge focuses that window

# dinky commands run on events. exec-and-forget gets $DINKY_WORKSPACE, $DINKY_PREV_WORKSPACE, $DINKY_DISPLAY.
# [hooks]
# startup = ['exec-and-forget brew services restart sketchybar']
# workspace-changed = ['exec-and-forget sketchybar --trigger workspace_change']
# focus-changed = []
# mode-changed = []

# Every rule whose conditions all match a new window runs, in order.
[[rules]]
app-id = 'com.apple.systempreferences'   # also: app-name, title (regexes), kind (normal|dialog|sheet|panel)
run = 'layout floating'

[mode.main]
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

[mode.service]
esc = ['reload-config', 'mode main']
r = ['flatten-workspace-tree', 'mode main']
alt-shift-h = ['join-with left', 'mode main']
alt-shift-j = ['join-with down', 'mode main']
alt-shift-k = ['join-with up', 'mode main']
alt-shift-l = ['join-with right', 'mode main']

```

With 5 workspaces, `alt-6` to `alt-9` do nothing until you raise `workspaces`.
