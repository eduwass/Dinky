---
id: din-5rp2
status: open
deps: [din-z1jw]
links: []
created: 2026-09-25T09:32:53Z
type: feature
priority: 0
assignee: Mikkel Malmberg
parent: din-eqz3
tags: [foundation, events]
---
# WindowServer event stream and window model

Replace polling with SLSRegisterNotifyProc notifications as JankyBorders does: window create, destroy, move, resize, reorder, level, hide, unhide, front app change, Space change. Feed a window model with lifetime-safe identity (window id plus pid plus creation), owner, frame, level, Space, and whether it is a normal window. AX observers only where WindowServer has no signal (title, minimize).

## Acceptance Criteria

Opening, closing, moving and switching Spaces all show up as events within a frame or two, on 27.0, with SIP on on the host. No timer polling remains except as a sanity reconcile.

