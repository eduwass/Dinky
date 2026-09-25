---
id: din-nwzf
status: open
deps: [din-mlu6]
links: []
created: 2026-09-25T09:32:53Z
type: feature
priority: 2
assignee: Mikkel Malmberg
parent: din-8wj4
tags: [spaces]
---
# Follow app activation (Cmd-Tab, Dock) with the fast switch

Port the spike's activation follower: on app activation, if its frontmost window is on another Space of the focused display, swipe there. Keep the guard that ignores activations right after a Space change (the Finder-on-empty-Space bounce). Config switching.follow-app-activation. Onboarding handles the native setting.

## Acceptance Criteria

Cmd-Tab to an app on another Space arrives in under 100 ms with no native slide. Arriving on an empty Space never bounces.

