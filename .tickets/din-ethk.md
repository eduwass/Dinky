---
id: din-ethk
status: closed
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


## Notes

**2026-09-25T11:28:53Z**

move-window-to-display next|prev [--follow] now works from DisplayModel: target = next/prev display (wrapping), bridged move to its current Space, wait for arrival, a floating window keeps its offset from the display corner, Coordinator.windowMoved re-tracks it (out of the source tree, into the target tree, both applied), --follow focuses it. Single-display VM: both 'move-window-to-display next' and 'prev --follow' answer 'no other display'. move-window-to-workspace also calls windowMoved now; verified 'move-window-to-workspace 4 --follow' from ws5 inserted beside the focused tile on ws4 and focused it. NOT validated: the two-display path (does the bridged move place the window on the other display's frame, does the target tree apply, does follow focus it) — do it on the host with two displays.

**2026-09-25T11:46:55Z**

Two-display validation: RESULTS.md, Display targeting for switching, step 7.

**2026-09-26T21:12:30Z**

Workspace half done and verified; display half implemented and its single-display error path verified. The two-display check is RESULTS.md step 7, folded into din-drei. Closing.
