---
layout: default
title: How it works
description: How dinky switches Spaces, moves and tiles windows, and what it cannot do.
permalink: /how-it-works/
---

# How it works

> **TL;DR:** A synthetic Dock swipe switches Spaces, a private SkyLight
> operation moves windows between them, and the public Accessibility API
> focuses and tiles. None of it touches the Dock's process or needs SIP off,
> but the private parts can break with any macOS update.

## Switching

macOS has no public way to switch Spaces quickly. The keyboard shortcuts
(Control-Arrow) play the full slide animation, about half a second each time.
A trackpad swipe does the same, but the Dock, which owns Spaces, finishes the
gesture instantly when the swipe is fast enough. So dinky pretends to be a
trackpad: it posts a synthetic Dock swipe gesture, with the private event
fields and serialized touch payload a real one carries, and an absurd
velocity. The Dock jumps straight to the target Space.

In testing that took 41 to 99 ms, median 66 ms, against about 560 ms for
Control-Arrow. The technique comes from mimi; Tuna and yabai use variants of
it. The Dock swipes the display under the pointer, so to switch another display
dinky briefly moves the pointer there and back.

Workspaces are the native Spaces, numbered 1 to N per display. dinky creates
missing Spaces on start, and again on a config reload, with a private SkyLight
operation similar to the one that moves windows. It never removes any.

### Following Cmd-Tab and the Dock

With the macOS setting "When switching to an application, switch to a Space
with open windows" off and `follow-app-activation` on, macOS only activates the
app, and dinky switches to the Space of the app's window with the same fast
swipe, preferring a window on the current Space.

Only activations a person caused are followed. macOS also activates apps on its
own, and chasing those would throw you off the Space you are on:

- Arriving on a Space activates whatever is there (Finder on an empty one). The
  first activation within 300 ms of a Space change is that one, and is ignored.
- When the active app quits, hides or loses its last window on the current
  Space, macOS activates another app. An activation within 300 ms of that is
  not followed.
- Opening a document activates the app before its new window exists. An app
  with no window on the current Space gets 250 ms for one to appear there
  before dinky follows it elsewhere.

## Moving

Moving a window to another Space goes through a private SkyLight
(WindowServer) operation, which took 3 to 14 ms in testing and needs no Dock
injection. After a move that does not follow, dinky focuses the window that
takes its place. `move-window-to-workspace --follow` switches and focuses the
moved window once the switch lands.

None of this touches the Dock's process or needs SIP off, which is what
separates dinky from yabai's full feature set. The cost is that the swipe event
format and the SkyLight operations are private and undocumented. They were
found by reading other projects' source and SkyLight's runtime, and a macOS
update can change or remove them without notice. One such change has already
happened: the simpler swipe form Tuna uses is ignored by the Dock on macOS 27,
as mimi notes. Expect dinky to need fixes after macOS updates, especially major
ones.

## Tiling

Focus and tiling use the public Accessibility API. dinky listens for
WindowServer notifications rather than polling, and keeps one layout tree per
Space, AeroSpace style.

- New windows tile as they appear. Dialogs, sheets, panels and windows that
  cannot be resized float without a rule, and
  [`on-window-detected`](configuration.md#on-window-detected) rules can float
  others. Floating windows keep their own position and size.
- Containers are `tiles` or `accordion`. In an accordion the children overlap
  and neighbours peek out by `accordion-padding`; the focused child is kept in
  front. A container's orientation is horizontal, vertical or `auto`, which
  follows its longer side.
- Native tab groups take over their tile in place. A window of the same app
  that appears at exactly a tile's frame, which is how Ghostty opens every new
  window, waits 250 ms: if the tile's window goes away in that time it was a
  tab switch and the newcomer takes the tile; otherwise it is tiled normally.
- Hidden apps are re-read so no empty tiles remain.
- Apps refuse some sizes. dinky learns each app's minimum size the first time
  it meets one, lays the workspace out around it, and remembers it across
  sessions in Application Support, so the re-flow happens once per app.

### Drag to swap

Dragging a tiled window with the mouse and dropping it over another tile swaps
the two. Dropped anywhere else, it snaps back to its tile. Only frames that
change while the mouse button is down count as a drag, so dinky's own frame
writes and apps moving themselves are left alone.

## Borders

dinky draws a border around every window on a visible Space: the focused one in
`active-color`, the rest in `inactive-color`. Each border is a dinky-owned
SkyLight window kept directly below its target, or above it as a click-through
ring with `order = 'above'`; it redraws only when its look or size changes. This
follows JankyBorders' approach, written from scratch. `exclude-apps` and
`only-apps` pick which apps get borders, and `enabled = false` turns them off.
See [`[borders]`](configuration.md#borders).

## Mission Control

On macOS 27, Mission Control, App Exposé and Show Desktop are drawn by
WindowManager, which orders in a display-sized window when they open and hides
it when they close. dinky watches for that window: while it is up, borders
hide and focus-follows-mouse stands down.

## Focus-follows-mouse

Off by default; turn it on with
[`[focus-follows-mouse]`](configuration.md#focus-follows-mouse). A listen-only
event tap watches the pointer, at most every 50 ms. A window the pointer comes
to rest on for `delay-ms` takes focus. Only real pointer movement counts, so
windows that move under a still pointer (a retile, a Space switch) never take
focus. Only windows dinky manages count; panels, menus, the menu bar, the Dock
and the desktop never do. Nothing happens while a mouse button is down, while a
menu is open, while Mission Control is up, or for 300 ms after a Space change or
a config reload.

## Recovery

Before dinky tiles a window, it journals the window's original frame and Space
to `~/Library/Application Support/dinky/journal.json`. Turning dinky off with
`enable off` or quitting it, including through `kill` and logging out, moves
every journaled window back to its Space and restores its frame.

After a crash, the next launch keeps the journal entries whose windows still
exist and offers to restore them: the menu shows "Restore N windows from the
previous session", and `dinky recover` does the same. Restoring leaves dinky
disabled; `dinky enable on` tiles again.

## Status

Every v1 command in `dinky help` is implemented and was verified in a macOS 27
VM. What has not yet been run anywhere is listed below.

## Known limits and what is unverified

- **Tested in a VM on a beta, with SIP off.** The switching, moving, focus and tiling results come from a macOS 27.0 beta VM (build 26A5416b) with SIP disabled, which is how the VM images ship. The binary was built on a host running 27.0 (26A428) with SIP on, but the full tests have not been rerun there. Nothing dinky does should need SIP off, but that is not yet confirmed.
- **One display only.** Every test ran on a single display. Multiple displays, switching a display that does not have the pointer, moving windows between displays and creating Spaces on a second display are untested.
- **Pointer warp.** To switch a display the pointer is not on, dinky moves the pointer there for about 60 ms and back. You may see a flicker.
- **Space creation** worked in the VM, including after restarting the Dock, but is untested on a host with SIP on. dinky cannot remove Spaces; use Mission Control.
- **Cmd-Tab following** was measured at 60 to 80 ms with `open -a`. Apps with windows on several Spaces, apps with no windows, and the real Cmd-Tab switcher are not yet tested.
- **Apps refuse some sizes.** Safari enforces a minimum width and Terminal snaps to its character grid, so tiles can overlap or leave gaps. dinky cannot force a size.
- **Focus across Spaces.** macOS cannot focus a window on another Space, so dinky switches first.
- **Private APIs.** See [Switching](#switching). A macOS update can break switching, moving or Space creation.
