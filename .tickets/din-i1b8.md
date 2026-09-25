---
id: din-i1b8
status: open
deps: [din-j2iv]
links: []
created: 2026-09-25T09:32:54Z
type: feature
priority: 2
assignee: Mikkel Malmberg
parent: din-eq4w
tags: [layout, edge-cases]
---
# Native tab groups, sheets and dialogs

Windows in a native tab group are one tile; inactive tabs never become tiles. Sheets and dialogs are attached to their parent for focus and moves. Minimized windows leave the tree and re-enter on unminimize.

## Acceptance Criteria

Safari with three tabs in one window is one tile. Minimizing and restoring a window re-tiles both times.

