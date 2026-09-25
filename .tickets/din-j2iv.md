---
id: din-j2iv
status: open
deps: [din-cc9k, din-j0o9]
links: []
created: 2026-09-25T09:32:53Z
type: feature
priority: 1
assignee: Mikkel Malmberg
parent: din-eq4w
tags: [layout, events]
---
# Automatic tiling driven by events

On window create: classify (normal, transient, floating rule), insert normal windows into the tree of their Space, apply. On destroy or move to another Space: remove and re-apply. On external Space change or display change: reconcile. Transients (sheets, dialogs, utility panels, non-resizable windows) float.

## Acceptance Criteria

Opening three windows tiles them as they appear. Closing one re-tiles. A Save sheet never becomes a tile. Moving a window with the native drag between Spaces is reconciled without dragging it back.


## Notes

**2026-09-25T10:49:05Z**

This is the integration ticket: wire WindowModel (via EventHub.shared.subscribe), DisplayModel, BorderManager and FrameApplier into the app through AppState, then the automatic tiling loop on top. Feed FrameApplier.minimumSizes back where cheap. Accordion/fullscreen stacking of the focused child must use activate plus raise (see din-yq3m note).
