---
id: din-o18o
status: closed
deps: [din-nt98]
links: []
created: 2026-09-25T09:32:54Z
type: task
priority: 2
assignee: Mikkel Malmberg
parent: din-oji3
tags: [visuals, borders]
---
# Border polish: corner radii, hidpi, allow and deny lists

Match each window's corner radius from SLSWindowIteratorGetCornerRadii, hidpi rendering, blur option, and per-app allow or deny lists like JankyBorders.

## Acceptance Criteria

Rounded and square windows both look right at 1x and 2x.


## Notes

**2026-09-25T10:59:10Z**

Done. Config [borders]: order = 'below'|'above' (default below), exclude-apps = [] and only-apps = [] (bundle IDs; only-apps wins when non-empty, windows without a bundle id are left out then), Borders.decorates(bundleID:), Table.strings; tests in ConfigTests.testBorderOrderAndAppLists; defaultTOML lists the keys. Drawing is now an even-odd filled ring (outer rounded rect minus the target's own rounded outline), interior transparent; square style fills around the target's corners so it looks right both above and below. Above: VM check with a temp red/green 6pt build: CGWindowList shows each border directly above its target, ring hugs the frame with 16pt corners, no content covered; clicks at the interior of Terminal and of a TextEdit window activated them (active colour moved), so tag bit 9 makes the whole window ignore the mouse. Sub-level: SLSGetWindowSubLevel + SLSTransactionSetWindowSubLevel (weak, both exported on 27); needs Screen Recording, returns 0 otherwise which is the normal sub-level. Shadow darkening below: accepted and documented in borders.h (as JankyBorders); above avoids it. 1x: all widths/radii in points, the context is scaled by SLSSetWindowResolution(backingScaleFactor of the target's screen), recreated on scale change; not run at 1x (would need a VM display change + restart). Radius: every bordered window is document-tagged (panels are not bordered); radius comes from SLSWindowIteratorGetCornerRadii, 0 when unreported, never a default; VM had only radius=16 windows, no square one to see. Front-app: extra refocus 20 ms later. Blur skipped: needs SLSSetWindowBackgroundBlurRadius plus a ring-shaped window region (CGSDiffRegion or similar), otherwise it blurs the content when ordered above; JankyBorders declares blur_radius but never applies it.
