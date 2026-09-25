---
id: din-19v3
status: open
deps: []
links: []
created: 2026-09-25T09:32:53Z
type: task
priority: 0
assignee: Mikkel Malmberg
parent: din-8wj4
tags: [spaces, spike]
---
# Spike: create Spaces with SLSBridgedSpaceCreateOperation

Try SLSBridgedSpaceCreateOperation (initWithOptions:values:) through the bridged dispatcher to add a user Space to a display, then verify Mission Control shows it, Dock stays coherent, and it survives a Dock restart. If it fails, document it; the fallback is asking the user to create desktops.

## Acceptance Criteria

A written result in RESULTS.md: works or not, on which build, with the exact call. If it works, a dinky function that creates one Space on a given display.

