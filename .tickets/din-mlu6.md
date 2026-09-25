---
id: din-mlu6
status: open
deps: [din-8j6i, din-j0o9, din-g6bk]
links: []
created: 2026-09-25T09:32:53Z
type: feature
priority: 1
assignee: Mikkel Malmberg
parent: din-8wj4
tags: [spaces, commands]
---
# Workspace commands on the focused display

workspace N, prev, next, workspace-back-and-forth, all acting on the focused display with the mimi swipe. Coalesce rapid requests to the newest target and confirm by observed Space change, not by submission.

## Acceptance Criteria

Ten alternating switches settle on the last request with no late jumps, on both displays.

