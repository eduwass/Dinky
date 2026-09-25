---
id: din-2h2u
status: open
deps: []
links: []
created: 2026-09-25T22:21:15Z
type: bug
priority: 2
assignee: Mikkel Malmberg
tags: [switching, fuzzing]
---
# Opening a document from another workspace follows the app to its old Space

open -a TextEdit b.txt (or opening a folder in Finder, a Dock click with a new window) activates the app before its new window exists. The follower sees the app's frontmost existing window on another Space and switches there, and the new window then opens on that Space or on the one left behind, so the user is moved away from where they asked for the document.

Reproduction (VM): TextEdit has a.txt on workspace 3. workspace 6 (empty); sleep 1.5; open -a TextEdit /tmp/r/b.txt. Log: 'activate TextEdit: followed 6 -> 3'. The display ends on 3.
Also: with a Finder window on workspace 1, 'open ~/Documents' from workspace 3 went to 1. Fuzzer seed 23 step 59: open /Applications switched Spaces during the idle period.

Idea: defer the follow by ~150 ms and re-check whether the app now has a window on the current Space before switching.

