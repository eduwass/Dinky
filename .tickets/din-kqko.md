---
id: din-kqko
status: open
deps: []
links: []
created: 2026-09-25T09:32:53Z
type: feature
priority: 1
assignee: Mikkel Malmberg
parent: din-eq4w
tags: [layout, tests]
---
# Layout tree model with pure tests

Per-Space tree: containers with orientation and ratios, leaves are windows. Insert beside the focused leaf by splitting its rectangle along the longer side, 50/50, deterministic tie-break. Remove collapses redundant containers keeping order. Flatten. Accordion is a container mode. Fullscreen is a per-Space overlay that hides the tree without changing it. Pure Swift, no AppKit, unit tests for every operation.

## Acceptance Criteria

Tests cover insert axes and ties, stable topology on resize, removal, flatten, accordion geometry with padding, fullscreen, and gaps arithmetic.

