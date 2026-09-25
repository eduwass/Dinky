---
id: din-g6bk
status: open
deps: [din-jf9s]
links: []
created: 2026-09-25T09:32:53Z
type: feature
priority: 1
assignee: Mikkel Malmberg
parent: din-eqz3
tags: [foundation, commands]
---
# Command dispatcher and vocabulary

Parse command strings like 'workspace 3', 'move-window-to-workspace 3 --follow', 'layout accordion', 'focus left', 'mode service' into typed commands and run them against the coordinator. One vocabulary for bindings, CLI and menu. Command list documented in one place.

## Acceptance Criteria

Every command in the PLAN.md config draft parses; unknown commands fail with a message naming the offending string.

