---
id: din-nt98
status: open
deps: [din-5rp2]
links: []
created: 2026-09-25T09:32:54Z
type: feature
priority: 1
assignee: Mikkel Malmberg
parent: din-oji3
tags: [visuals, borders]
---
# Focus borders on SkyLight windows

Reimplement JankyBorders' approach (GPL, no code lifted): one border window per managed window created with SLSNewWindow, ordered directly above or below its target with SLSTransactionOrderWindow, moved and resized from the event stream, drawn with active or inactive colour, width and style from config. Works on every display and Space. Hidden for full-screen and minimized windows.

## Acceptance Criteria

Borders track windows during native drags and dinky re-tiles without lag or flicker. Focus change recolours within a frame. Works with SIP on on the host, on 27.0.

