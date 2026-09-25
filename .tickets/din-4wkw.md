---
id: din-4wkw
status: open
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

