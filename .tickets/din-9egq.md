---
id: din-9egq
status: open
deps: []
links: []
created: 2026-09-25T22:21:15Z
type: bug
priority: 1
assignee: Mikkel Malmberg
tags: [layout, fuzzing]
---
# Tiles shift two or three times when a window refuses its size

FrameApplier learns minimum sizes only from readback: write, settle 0.1 s, read, rewrite, settle, read, record, then the completion re-lays the tree out around the new minimum. Each refusal found costs one more visible layout, so a tree with Safari (574 pt minimum width) and narrow TextEdit tiles moves every tile two or three times within about 0.6 s, and in the fuzzer the last pass sometimes lands more than 0.8 s after the action. This is a likely source of the 'weird shifting around'.

Reproduction (VM): on an empty workspace open three TextEdit documents, then open -a Safari while sampling debug-state every 100 ms. Seen:
0.93 s: TextEdit tile 19853 shrinks to 246 wide, Safari at 770,375 574x328 (runs off the 1024 pt screen)
1.25 s: 19846 500 -> 418 wide, 19849 moves to x 434
1.52 s: 19846 418 -> 303, 19849 to x 319 and 697 wide, 19853 115 wide
Fuzzer: seed 23 steps 5, 6, 12; seed 31 steps 11, 24, 41, 54 (shift-frame).

Ideas: record the minimum from the first readback instead of after the retry; lay the tree out again once per batch, not per app queue; seed minimums from kAXMinimumSize-like hints where apps expose them; or keep a per-app minimum so a new Safari window starts with it.

