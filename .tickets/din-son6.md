---
id: din-son6
status: open
deps: [din-19v3, din-j0o9]
links: []
created: 2026-09-25T09:32:53Z
type: feature
priority: 1
assignee: Mikkel Malmberg
parent: din-8wj4
tags: [spaces]
---
# Ensure workspace count on start and reload

For each display, if it has fewer user Spaces than config workspaces, create the missing ones. Never remove. Report in the log and menu bar if creation is unavailable.

## Acceptance Criteria

With workspaces = 5 and a fresh display with one Space, dinky creates four. Extra Spaces are left alone.

