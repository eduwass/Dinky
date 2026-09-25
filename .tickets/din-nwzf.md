---
id: din-nwzf
status: closed
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


## Notes

**2026-09-25T11:00:26Z**

Delivered inside din-j0o9 and din-mlu6: activation follower switches the target window's display with the mimi swipe, per-display last-seen guard, config switching.follow-app-activation, onboarding handles the native setting. Verified in the VM (TextEdit 62 to 77 ms). Closing.
