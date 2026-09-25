---
id: din-yq3m
status: open
deps: [din-j2iv]
links: []
created: 2026-09-25T09:32:54Z
type: feature
priority: 1
assignee: Mikkel Malmberg
parent: din-eq4w
tags: [layout]
---
# Accordion container mode

layout accordion on the focused container: children overlap within the container rectangle, the focused child on top and full size minus padding, neighbours offset by accordion-padding along the container's axis. Order stable, split ratios remembered for toggling back to tiles. Focus commands move through the accordion order.

## Acceptance Criteria

A three-window accordion cycles with focus commands and Cmd-Tab, the intended child is frontmost every time, and toggling back to tiles restores the previous ratios.

