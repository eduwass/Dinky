---
id: din-bcfy
status: open
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

