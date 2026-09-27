---
layout: default
title: Documentation
description: A tiling window manager for macOS that leaves System Integrity Protection on.
permalink: /
---

# Tiling on native Spaces, SIP left on.

<p class="tagline">oh wow. you moved a rectangle.</p>

> **TL;DR:** dinky tiles the windows on each native Space, switches Spaces
> in about 70 ms instead of half a second, and draws a border around the
> focused window. Nothing is injected into the Dock.

<pre><code>$ dinky workspace 3
$ dinky list-windows --workspace 3
4211 | Ghostty | ~
4388 | Safari  | dinky
$ dinky layout accordion <span class="cursor">█</span></code></pre>

Latest release: **{{ site.version }}**

Workspaces are native Spaces, switched with the same Dock gesture a trackpad
sends. Windows tile automatically as they open, with an accordion mode, focus
borders, a TOML config, and a `dinky` command line for scripts and bars.

It is not a compositor: macOS still draws every window, and dinky can only ask
apps to move and resize. It has no scrolling or infinite-canvas layouts and no
animations.

Status: early, in daily use by its author on macOS 27. Expect rough edges.

> **Private APIs.** macOS has no public way to switch Spaces quickly or move a
> window to another Space. dinky uses a synthetic Dock swipe and a few private
> SkyLight calls to do both. They were found by reading other projects' source
> and SkyLight's runtime, and a macOS update can change or remove them without
> notice. Only macOS 27.0 has been tried. Expect dinky to need fixes after
> macOS updates, especially major ones.

## Requirements

- **macOS 27.** Only 27.0 has been tried.
- **Apple silicon.** Intel Macs have not been tried, and macOS 27 runs on
  Apple silicon only.
- **Accessibility permission.** dinky moves and resizes windows and listens
  for its key bindings through the Accessibility API. The first run asks for
  it.
- **The Cmd-Tab setting.** macOS has a setting, "When switching to an
  application, switch to a Space with open windows" (System Settings > Desktop
  & Dock > Mission Control). With it on, Cmd-Tab or a Dock click to an app on
  another Space plays the slow slide animation. With it off, macOS only
  activates the app, and dinky switches to the app's Space itself, fast. The
  first run offers to turn it off. Turning it off restarts the Dock. You can
  say no; everything else works.

## Install

With Homebrew, which also puts the `dinky` command line on your `PATH`:

```sh
brew install --cask mikker/tap/dinky
open -a dinky
```

Or download the signed, notarized app:

```sh
curl -fLO https://github.com/mikker/Dinky/releases/latest/download/dinky.app.zip
unzip dinky.app.zip
mv dinky.app /Applications/
open /Applications/dinky.app
```

Or [download dinky.app.zip](https://github.com/mikker/Dinky/releases/latest/download/dinky.app.zip)
in a browser and drag `dinky.app` to Applications. dinky is a menu bar app with
no Dock icon. It updates itself with Sparkle; the menu has "Check for
Updates…".

The app binary is also the command line tool. Installed by hand, link it onto
your `PATH`:

```sh
ln -s /Applications/dinky.app/Contents/MacOS/dinky /usr/local/bin/dinky
```

## Install from source

Building needs Xcode or the Swift 6 toolchain and
[`just`](https://github.com/casey/just).

```sh
git clone https://github.com/mikker/Dinky.git
cd Dinky
just install     # builds and signs build/dinky.app, symlinks the CLI into ~/.local/bin
open build/dinky.app
```

`just bundle` runs `scripts/bundle.sh` on its own, which builds a release
binary and puts the signed app at `build/dinky.app`. `just bundle --debug`
builds a debug one; `just run` builds a debug bundle and runs it attached so
the log streams to the terminal.

The script signs with the identity in `IDENTITY`, which defaults to the
author's certificate, so set it to one of yours
(`security find-identity -p codesigning` lists them):

```sh
IDENTITY="Apple Development: Your Name (TEAMID)" just install
```

A stable identity matters: macOS ties the Accessibility grant to the
signature, and with ad-hoc signing (`IDENTITY=-`) every rebuild loses the
grant. `VERSION` and `BUILD` set the bundle version. Move `build/dinky.app`
to `/Applications` if you like.

## First run

1. dinky writes the default config to `~/.config/dinky/dinky.toml` if there is
   none.
2. A window asks for Accessibility. "Open Accessibility Settings" takes you to
   Privacy & Security > Accessibility; turn dinky on there. The window moves on
   by itself once it is allowed.
3. Once, dinky offers to turn off "switch to a Space with open windows"
   (above). "Turn It Off" runs
   `defaults write com.apple.dock workspaces-auto-swoosh -bool false` and
   restarts the Dock. "Leave It" keeps the setting and does not ask again.
4. The menu bar shows the current Space number. Its menu switches workspaces,
   moves the focused window, toggles dinky on and off, reloads the config and
   quits.

The shipped config has `start-at-login = true`, so dinky registers itself as a
login item.

`dinky doctor` checks the rest: that the config parses and every binding, rule
and callback names a real command, that "Automatically rearrange Spaces based
on most recent use" is off (otherwise workspace numbers move around), the
Cmd-Tab setting, how many workspaces each display has, and whether the app is
running. It exits 1 on errors.

## Uninstall

Quit dinky from its menu, delete the app and `~/.config/dinky`, and remove it
from Accessibility and Login Items in System Settings. To get the Cmd-Tab slide
back:

```sh
defaults write com.apple.dock workspaces-auto-swoosh -bool true && killall Dock
```

## Known limits

- **One display is what has been tested.** Switching a display the pointer is
  not on moves the pointer there for about 60 ms and back; you may see a
  flicker.
- **dinky cannot remove Spaces.** It creates the ones the config asks for and
  never removes any; use Mission Control.
- **Apps refuse some sizes.** Safari enforces a minimum width and Terminal
  snaps to its character grid, so tiles can overlap or leave gaps. dinky learns
  each app's minimum size and lays the workspace out around it.
- **Focus across Spaces.** macOS cannot focus a window on another Space, so
  dinky switches first.
- **Private APIs.** A macOS update can break switching, moving or Space
  creation.

## Start here

- [Configuration](configuration.md)
- [Commands, the CLI and SketchyBar](commands.md)
- [Source](https://github.com/mikker/Dinky)

## Credits

dinky studies the approaches of these projects. Where code was adapted, the
license is noted.

- [yabai](https://github.com/asmvik/yabai) (MIT): SkyLight function
  signatures, window filtering, focus and WindowServer event handling. dinky
  uses only yabai's SIP-on paths, not its scripting addition.
- [mimi](https://github.com/y3owk1n/mimi) (MIT): the augmented Dock swipe that
  makes switching fast, and the Mach-O symbol lookup for the bridged SkyLight
  operations.
- [AeroSpace](https://github.com/nikitabobko/AeroSpace) (MIT): the key
  syntax, the command vocabulary and the accordion layout.
- [JankyBorders](https://github.com/FelixKratz/JankyBorders) (GPL-3.0):
  studied only. dinky's borders and WindowServer notifications follow its
  approach but are written from scratch.
- [Tuna](https://tunaformac.com): an earlier synthetic Dock swipe, studied.
- [bobrwm](https://github.com/bobrwm/bobrwm) (MIT): studied for creating Spaces
  with the bridged SkyLight operation.

dinky is MIT licensed; see
[LICENSE](https://github.com/mikker/Dinky/blob/main/LICENSE).
