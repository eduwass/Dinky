---
id: din-bcfy
status: closed
deps: [din-uutc]
links: []
created: 2026-09-25T09:32:54Z
type: feature
priority: 2
assignee: Mikkel Malmberg
parent: din-eq4w
tags: [layout, commands]
---
# Resize smart, fullscreen toggle, flatten

resize smart +/-N grows or shrinks the focused tile along its container's axis, adjusting sibling ratios; resize width|height too. fullscreen toggles the focused tile to fill the Space (minus outer gaps) while the tree is kept; any layout command or focus change exits it. flatten-workspace-tree resets nesting.

## Acceptance Criteria

Resize steps are visible and bounded by minimum sizes. Fullscreen and back leaves the layout unchanged.


## Notes

**2026-09-25T11:28:53Z**

resize smart|width|height: Workspace.resize(by:along:) takes the nearest tiles container (width -> horizontal, height -> vertical), clamps at minimumRatio and at the window's minimum size, keeps sibling ratios proportional, and undoes a step the minimum sizes would swallow whole. Minimum sizes: Workspace.minimumSizes feeds layout(); tiles grow to a window's recorded minimum and siblings give in proportion, stopping at their own minimums (fit()); ignored when the minimums do not all fit. The Coordinator copies FrameApplier.minimumSizes in before every apply and re-applies once when an apply recorded a new one. fullscreen toggles; any focus change to another window, move, join, resize, layout or flatten ends it; tree untouched. VM: resize smart/width steps visible (500->550->599), height on a window with no vertical container 'nothing to do', -5000 clamps at 10%, further shrink 'nothing to do'; fullscreen and back left all frames identical; fullscreen + focus left exited with frames identical; fullscreen + resize exited. Notes (min width 701) beside w1: w1 299 + Notes 701, no overlap; resize +100 on w1 and -100 on Notes both 'nothing to do'. flatten-workspace-tree -> three equal columns. Engine tests: ResizeAxisTests, MinimumSizeTests, FullscreenExitTests.
