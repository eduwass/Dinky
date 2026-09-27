---
id: din-ame0
status: open
deps: []
links: []
created: 2026-09-27T22:00:35Z
type: bug
priority: 1
assignee: Mikkel Malmberg
tags: [switching, fuzzing]
---
# Follow loop between two apps on the host

Reported 27 September 2026: dinky sometimes switches Spaces between two apps without end, possibly after an app closes and macOS activates a fallback app. Not reproduced in the VM: 5 seeds x 80 steps of scripts/fuzz.py --switching (quits, closes, activations, native and dinky switches, pointer moves with focus-follows-mouse on, native full-screen toggles) on one display, with the h-loop invariant (three or more Space changes while idle) never firing. The switcher retries a swipe once and gives up, and the follower never follows an app that has a window on the focused display's current Space, so a loop needs a late arrival activation (seen once: 'activate Finder: followed 2 -> 6' after landing on an empty workspace, so arrivals can come later than the 300 ms arrivalWindow) or two displays, which the VM cannot test. Mitigation shipped: the follower pauses for 5 s after 4 follows within 3 s and logs the trail, and the bundled app now logs to ~/Library/Logs/dinky.log. Next: wait for a trail from the host and read it.

