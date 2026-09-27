---
layout: default
title: Commands
description: dinky commands, the command line and socket, and scripting a bar.
permalink: /commands/
---

# Commands

> **TL;DR:** Key bindings, `dinky <command>` and the menu bar share one
> vocabulary. `dinky help` prints it.

<div class="wide-table" markdown="1">

| Command | What it does |
|---|---|
| `workspace <number\|prev\|next>` | Switch the focused display to a workspace (a native Space), numbered from 1. `prev` and `next` do not wrap. |
| `workspace-back-and-forth` | Switch to the workspace that was focused before the current one. |
| `move-window-to-workspace <number\|prev\|next> [--follow]` | Move the focused window to a workspace. With `--follow`, switch there too. |
| `move-window-to-display <next\|prev> [--follow]` | Move the focused window to the next or previous display's current workspace. With `--follow`, focus it there. |
| `focus <left\|down\|up\|right> [--boundaries <b>] [--boundaries-action <a>]` | Focus the nearest window in a direction. `--boundaries` is `workspace` (the default) or `all-monitors-outer-frame`, which at the workspace edge goes on to the display in that direction and focuses its window nearest that edge. `--boundaries-action` says what happens at the last edge: `stop` (the default), `fail`, `wrap-around-the-workspace`, or, with `all-monitors-outer-frame`, `wrap-around-all-monitors`. `--wrap-around` is short for `--boundaries-action wrap-around-the-workspace`. Never switches workspace. |
| `focus-monitor <left\|down\|up\|right\|next\|prev>` | Focus a display: its most recently focused window, or, when its workspace is empty, the display itself, so workspace commands act on it until focus next changes. |
| `move <left\|down\|up\|right>` | Move the focused window in a direction within the layout tree. |
| `join-with <left\|down\|up\|right>` | Put the focused window and its neighbour in a new container. |
| `resize <smart\|width\|height> <+N\|-N>` | Grow or shrink the focused window by N points: `smart` along its container, `width` or `height` along that axis. |
| `layout <tiles\|accordion\|horizontal\|vertical\|auto\|h_tiles\|v_tiles\|h_accordion\|v_accordion\|floating\|tiling>...` | Set the layout of the focused window's container, or float or tile the window. `tiles` and `accordion` set the mode, `horizontal`, `vertical` and `auto` (follow the container's longer side) the orientation, `h_accordion` and the like both. With several, apply the first that does not describe the window now, so `layout floating tiling`, `layout tiles accordion` and `layout horizontal vertical` toggle. An `auto` container counts as the orientation it follows now. |
| `fullscreen` | Toggle the focused window filling the workspace. The tree is kept. This is not macOS full screen. |
| `flatten-workspace-tree` | Put every window on the workspace back into one flat container. |
| `balance-sizes` | Give every window on the focused workspace an equal share of its container. |
| `retile` | Re-read every window and re-apply the layout of every workspace on screen. |
| `mode <name>` | Switch to a binding mode from the config, such as `main` or `service`. |
| `reload-config` | Reload `~/.config/dinky/dinky.toml`. On an error the previous config stays. |
| `enable <on\|off\|toggle>` | Turn dinky's key bindings and app-activation following on or off. |
| `list-workspaces [flags]` | Print workspace numbers. See [Scripting and SketchyBar](#scripting-and-sketchybar). |
| `list-windows [flags]` | Print windows as `id \| app \| title`. See below. |
| `list-monitors [flags]` | Print displays as `number \| name`. `list-displays` is the same. |
| `debug-state` | Print the tiling state as JSON: displays, each workspace's tree and expected frames, placements and windows. For tests and bug reports. |
| `exec-and-forget <shell command>` | Run the rest of the line with `/bin/sh -c` without waiting. Its output goes to dinky's log. |

</div>

Workspaces are counted per display, and workspace commands act on the display that has focus. A full-screen app's Space is not a numbered workspace; workspace commands there answer "not on a numbered workspace".

## Command line and socket

The app binary is also the command line tool. Link it onto your `PATH`:

```sh
ln -s /Applications/dinky.app/Contents/MacOS/dinky /usr/local/bin/dinky
```

`just install` from source links `build/dinky.app`'s binary into `~/.local/bin` instead.

Then `dinky <command>` runs any command above in the running app, for example `dinky workspace 3` or `dinky list-windows`. The CLI checks the command first and prints the expected syntax if it does not parse. It exits 0 on success and 1 on an error or when the app is not running. Run from a shell with no arguments, the binary prints usage instead of starting the app; `dinky app` starts the app in the foreground, which is handy for seeing its log.

The CLI talks to the app over a unix socket at `$TMPDIR/dinky.sock` (your per-user temp directory; `dinky help` prints the full path). The protocol is one command per connection: write the command line ending in a newline, and read the answer, a first line of `ok` or `error` followed by the reply text. So scripts can skip the CLI:

```sh
printf 'workspace 2\n' | nc -U "$TMPDIR/dinky.sock"
```

A few subcommands are for the command line only:

| Command | What it does |
|---|---|
| `app` | Run the app in the foreground, logging to the terminal. |
| `recover` | Ask the running app to restore the windows a crashed session left tiled. See [Recovery](#recovery) below. |
| `debug events\|windows` | Print the live window event stream, or the current windows, without the app. Useful in a bug report. |
| `doctor [--config <path>]` | Check the config and the macOS settings dinky depends on. Exits 1 on errors. |

`dinky debug-state` asks the app for its tiling state as JSON (displays, each workspace's tree with the frames it expects, placements and windows). For testing, `dinky debug ax-close|ax-minimize|ax-unminimize <window id>`, `dinky debug ax-frame <window id> <x> <y> <w> <h>` and `dinky debug hide-app|unhide-app <pid>` act on windows and apps through Accessibility; `just fuzz <seed> <steps>` uses them to fuzz the app in the test VM (`scripts/fuzz.py`).

## Recovery

Before dinky tiles a window, it journals the window's original frame and Space
to `~/Library/Application Support/dinky/journal.json`. Turning dinky off with
`enable off` or quitting it, including through `kill` and logging out, moves
every journaled window back to its Space and restores its frame.

After a crash, the next launch keeps the journal entries whose windows still
exist and offers to restore them: the menu shows "Restore N windows from the
previous session", and `dinky recover` does the same. Restoring leaves dinky
disabled; `dinky enable on` tiles again.

## Scripting and SketchyBar

The queries follow [AeroSpace](https://nikitabobko.github.io/AeroSpace/commands)'s names, flags and output, so bar scripts written for AeroSpace mostly work by changing `aerospace` to `dinky`: `aerospace list-windows --workspace 3` becomes `dinky list-windows --workspace 3` with the same output. The difference is that dinky's workspaces are numbers per display, so with two displays the numbers repeat.

### Queries

Each prints one line per item. Without a display flag they cover the focused display.

<div class="wide-table" markdown="1">

| Query | Flags | Default output |
|---|---|---|
| `list-workspaces` | `--all` (every display), `--focused` (the focused workspace), `--monitor <focused\|all\|n>...`, `--visible [no]`, `--empty [no]`, `--format` | `%{workspace}` |
| `list-windows` | `--all`, `--focused` (the focused window), `--monitor <focused\|all\|n>...`, `--workspace <focused\|visible\|n>...` (repeatable), `--app-bundle-id <id>`, `--format` | `%{window-id}%{right-padding} \| %{app-name}%{right-padding} \| %{window-title}` |
| `list-monitors` | `--focused [no]`, `--format` | `%{monitor-id}%{right-padding} \| %{monitor-name}` |

</div>

`--format` takes a string with `%{variable}`s; quote it. `%{right-padding}` pads to line up columns, `%{newline}` and `%{tab}` insert those characters.

- Workspaces: `%{workspace}` (the number), `%{workspace-is-focused}`, `%{workspace-is-visible}`, `%{monitor-id}` (1-based display number), `%{monitor-name}`, `%{monitor-is-main}`.
- Windows: `%{window-id}`, `%{window-title}`, `%{window-layout}` and `%{window-parent-container-layout}` (`h_tiles`, `v_tiles`, `h_accordion`, `v_accordion`, `floating` or `fullscreen`; an `auto` container reports the orientation it follows now), `%{window-is-floating}`, `%{window-is-fullscreen}`, `%{app-name}`, `%{app-bundle-id}`, `%{app-pid}`, plus the workspace and monitor variables.
- Monitors: `%{monitor-id}`, `%{monitor-name}`, `%{monitor-is-main}`.

`dinky list-workspaces --all` prints every display's numbers, so `for sid in $(dinky list-workspaces --all)` repeats them on two displays; `--format '%{monitor-id}-%{workspace}'` tells them apart.

### Hooks

The config's `[hooks]` table runs dinky commands on events; see [Configuration](configuration.md#hooks). A bar is driven with `exec-and-forget`:

```toml
[hooks]
# Once dinky has read the windows and displays.
startup = ['exec-and-forget brew services restart sketchybar']
# Whenever a display's current workspace changes, by dinky or natively.
workspace-changed = ['exec-and-forget sketchybar --trigger workspace_change WORKSPACE=$DINKY_WORKSPACE']
# When the focused window changes (debounced by 50 ms) and when the binding mode changes.
focus-changed = ['exec-and-forget sketchybar --trigger focus_changed']
mode-changed = ['exec-and-forget sketchybar --trigger mode_changed']
```

`workspace-changed` runs its `exec-and-forget` with `DINKY_WORKSPACE` (the new number, empty on a full-screen app's Space), `DINKY_PREV_WORKSPACE` and `DINKY_DISPLAY` (the 1-based number of the display that switched) in the environment. Programs started by `exec-and-forget` find Homebrew's `/opt/homebrew/bin` on `PATH`. Apart from `startup`, nothing fires while dinky starts up.
