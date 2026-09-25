---
id: din-mekd
status: closed
deps: [din-j2iv, din-jf9s]
links: []
created: 2026-09-25T09:32:54Z
type: feature
priority: 2
assignee: Mikkel Malmberg
parent: din-eq4w
tags: [layout, config]
---
# Floating rules and toggle

on-window-detected rules in config: match app-id, title regex, window kind; run commands such as layout floating or move-window-to-workspace. layout floating tiling toggles the focused window; floating windows keep their frame and are not in the tree.

## Acceptance Criteria

A rule for System Settings floats it on open. Toggling a tiled window to floating leaves the others re-tiled; toggling back inserts beside the focused tile.


## Notes

**2026-09-25T11:28:53Z**

layout floating|tiling and 'layout floating tiling' toggle the focused window (Coordinator.setFloating): floating leaves the tree and keeps its frame, tiling re-inserts beside the focused tile; tiles/accordion on a floating window tile it first. Rules: Config.commands(for:) returns the matching rules' commands; 'layout floating' floats at classification, every other command runs once for that window through Dispatcher.run(_:window:) (internal parameter, not CLI). VM: w3 floated kept 308,375 708x96 and Preview took the column; toggled back it went under Preview (the focused tile); System Settings opened floating with the tree untouched; a temporary rule (title 'cmds-rule' -> move-window-to-workspace 5) sent a new TextEdit window to ws5, tiled there when shown, ws4 tree unchanged (config restored afterwards). Caveat: the 'open -a TextEdit' activation that follows was then followed by the activation follower to TextEdit's window on ws3.
