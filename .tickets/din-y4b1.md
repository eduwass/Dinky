---
id: din-y4b1
status: closed
deps: []
links: []
created: 2026-09-25T22:21:15Z
type: bug
priority: 1
assignee: Mikkel Malmberg
tags: [layout, fuzzing]
---
# Same-app window at a tile's exact frame displaced that tile (tab heuristic)

Coordinator.tab(replacedBy:in:) treated any newly shown window of the same app at exactly a tile's frame as a native tab and let it take the tile; the displaced window was left untracked, lying under the newcomer. Hit by Ghostty on the user's Mac (every new window opens at the previous window's frame), by moving a window back to a Space where its sibling fills the same frame, and by unminimizing a window whose old frame now equals a sibling's tile. The two untracked windows could also swap in and out of the tree on later events.

Reproduction (VM, TextEdit, before the fix):
1. workspace 3 (empty); open -a TextEdit a.txt; open -a TextEdit b.txt
2. move-window-to-workspace 4 --follow (b alone on 4, full frame)
3. open -a TextEdit b.txt (focus b); move-window-to-workspace 3 --follow
Result: tree of 3 holds only b; a is shown but untracked (debug-state placement space 0).
Also: minimize a (alone, full frame), open b (full frame), unminimize a -> b untracked. And: tile A, minimize its sibling B, debug ax-frame B to A's frame, unminimize B -> A untracked.

Fixed 26 September: a window arriving from another Space's tree is never a tab, and a same-frame newcomer is held out of the tree for 250 ms; if the tile's window is ordered out, minimized or closed in that time it is a tab switch and the newcomer takes the tile, otherwise the newcomer is tiled normally. TextEdit Merge All Windows plus Show Next/Previous Tab and closing a tab still keep one tile in place.

