---
id: din-mekd
status: open
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

