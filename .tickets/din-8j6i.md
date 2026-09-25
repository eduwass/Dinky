---
id: din-8j6i
status: open
deps: []
links: []
created: 2026-09-25T09:32:53Z
type: task
priority: 0
assignee: Mikkel Malmberg
parent: din-8wj4
tags: [spaces, spike, displays]
---
# Spike: fast switch on a display without the cursor

The Dock swipe acts on one display. Find how to target a display: mimi's per-display handling, yabai's display focus adjustment, cursor warp during the swipe, or the swipe event's display fields. Measure on two displays on the host.

## Acceptance Criteria

workspace N switches the focused display, not the cursor's, reliably, with the chosen technique documented in RESULTS.md.

