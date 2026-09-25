---
id: din-ethk
status: open
deps: [din-mlu6, din-j2iv]
links: []
created: 2026-09-25T09:32:53Z
type: feature
priority: 1
assignee: Mikkel Malmberg
parent: din-8wj4
tags: [spaces, commands]
---
# Move window to workspace and to display

move-window-to-workspace N [--follow] with the bridged operation; move-window-to-display next|prev|<name> [--follow] by moving the window to the target display's current Space and re-tiling both. Sheets travel with parents (verified in the spike).

## Acceptance Criteria

Moving keeps the source layout intact and inserts the window into the target tree. Follow lands focus on the moved window.

