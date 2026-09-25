---
id: din-cc9k
status: open
deps: [din-kqko, din-5rp2]
links: []
created: 2026-09-25T09:32:53Z
type: feature
priority: 1
assignee: Mikkel Malmberg
parent: din-eq4w
tags: [layout]
---
# Frame applier with gaps, per-app coalescing and readback

Turn tree rectangles into AX writes: gaps applied, AXEnhancedUserInterface cleared, size-position-size, one queue per app so a slow app blocks only itself, newest frame wins, readback after settle, bounded correction for windows that refuse a size (no retry loops).

## Acceptance Criteria

Five windows including Safari and a terminal land where computed or report a bounded DIFF once. A hung app does not delay the others.

