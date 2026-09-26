---
id: din-9egq
status: closed
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


## Notes

**2026-09-25T22:37:34Z**

Cause: the second and third passes are a chain, not refusals found separately. Pass 1 asks Safari for 246 wide, it refuses (574). The corrected layout grows Safari's column to exactly its minimum extent, so the TextEdit tile beside it is asked for 0 wide; it refuses (115) and that needs a third layout. Refusals in one pass were already collected into one completion. Fix: minimums are remembered per bundle id for the session, so a new window of an app that has refused before is laid out around its minimum from the start; the scheduler neither rewrites nor retries a window that is already where its recorded minimum lets it be; minimums found in different dimensions are merged, where before the later one overwrote the earlier; the completion re-lays out through edit(), so only when the layout changes. VM reproduction (three TextEdit docs, then open -a Safari, debug-state every 100 ms): before, 3 frame sets with Safari every run; after, 1 set once TextEdit and Safari minimums are known (runs 2 and 3), still 3 passes on the first encounter in a fresh session (a TextEdit minimum is only found by squeezing a TextEdit window). Fuzz seed 23, 100 steps: no shift-frame (was x11 in 150 steps); shift-space x3 (activation following, not frames). Open: the first-encounter chain; options are a floor for tiles with unknown minimums when a sibling's minimum takes space, or recording a minimum from the first readback to shorten each pass by one settle and retry.

**2026-09-26T21:12:30Z**

Fixed except the first encounter with an app's minimum, which now happens once ever: minimums are remembered per app across sessions (6a3126f). The remaining first-encounter chain is accepted. Closing.
