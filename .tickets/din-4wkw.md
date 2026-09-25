---
id: din-4wkw
status: closed
deps: []
links: []
created: 2026-09-25T22:21:15Z
type: bug
priority: 1
assignee: Mikkel Malmberg
tags: [switching, fuzzing]
---
# Quitting or hiding the front app throws the display to another Space

When the front app quits or hides, macOS activates another app (often Finder). The activation follower treats that like a Cmd-Tab and switches to that app's frontmost window's Space, so the user is thrown off the workspace they are on. Likely part of the 'weirdness when switching to empty spaces' report: quitting the only app on a workspace sends you elsewhere.

Reproduction (VM): Finder has a window on workspace 6; TextEdit's only window is on workspace 5 and it is front there. pkill -x TextEdit (as Cmd-Q). Log: 'activate Finder: followed 5 -> 6'; the display is now on 6.
Fuzzer: seed 32 steps 53 (hide), 72 (quit); seed 33 steps 63, 133 (quit), 103, 109, 122 (hide) (g-bounce).

Idea: only follow activations the user asked for: ignore an activation that arrives right after the previously front app terminated or hid (NSWorkspace didTerminate/didHide), or ignore Finder activations unless Finder was chosen explicitly.


## Notes

**2026-09-25T22:44:28Z**

Fixed in ActivationFollower.swift (follower split out of SpaceSwitching.swift). The follower remembers the active app and when an app last quit, hid (NSWorkspace) or lost a window (WindowServer close/destroy, by pid). An activation within 300 ms of the previously active app going away, while that app shows no window on a current Space, is macOS replacing it and is not followed; decided after the 250 ms window grace, so notification order does not matter. VM: Finder window on 6, TextEdit's only window on 5; pkill -x TextEdit and debug hide-app both stay on 5 ('activate Finder: not followed, macOS replaced the app that went away'). Seed 33, 100 steps: no g-bounce (was x5 in 150).
