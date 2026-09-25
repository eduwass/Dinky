---
id: din-uutc
status: open
deps: [din-j2iv, din-g6bk]
links: []
created: 2026-09-25T09:32:54Z
type: feature
priority: 1
assignee: Mikkel Malmberg
parent: din-eq4w
tags: [layout, commands]
---
# Directional focus, move, swap and join-with

focus left|right|up|down by geometry within the Space, across containers. move <dir> swaps with the neighbour or moves out of the container at the edge. join-with <dir> puts the focused window into the neighbour's container, creating one if needed. Focus uses AX raise plus activate (proven in the spike).

## Acceptance Criteria

In a three-window layout every direction from every window does what i3 would do. Focus never switches Spaces.

