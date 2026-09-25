---
id: din-w0m5
status: open
deps: [din-g6bk]
links: []
created: 2026-09-25T09:32:54Z
type: feature
priority: 1
assignee: Mikkel Malmberg
parent: din-zyzn
tags: [hotkeys]
---
# Hotkey engine with modes and chained commands

Event tap on key down; parse AeroSpace key syntax (alt-shift-h, ctrl-left, esc) into keycode and modifiers; bindings per mode; a binding runs one command or a list; mode <name> switches. Self-posted events are tagged and passed through. Bindings from config, replaced on reload.

## Acceptance Criteria

The PLAN.md default bindings work, including the service mode round trip. A key not bound passes to the app untouched.

