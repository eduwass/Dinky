---
id: din-yq3m
status: closed
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


## Notes

**2026-09-25T11:28:40Z**

layout accordion|tiles and 'layout accordion tiles' toggle the focused window's container (Dispatcher.layout: first name that does not describe the current state). Verified in the VM: column accordion (2 children) and root accordion (3 TextEdit windows) cycle with focus up/down/left/right in child order, the focused child frontmost in CG order after every step; toggling back to tiles after a 'resize height +60' gave identical frames (ratios kept; engine test added). Cmd-Tab (real CGEvent Cmd-Tab) between Preview and Notes inside a 6-window root accordion: 4/4 times the activated child was frontmost and focused on the same Space. Caveat: Cmd-Tab into TextEdit sometimes jumped to another Space because the activation follower picks TextEdit's window on ws3 (another agent's d.txt) — SpaceSwitching's choice of window, not the accordion.
