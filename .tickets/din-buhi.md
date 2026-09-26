---
id: din-buhi
status: closed
deps: []
links: []
created: 2026-09-26T20:23:18Z
type: feature
priority: 1
assignee: Mikkel Malmberg
tags: [layout]
---
# Accordion orientation: auto and layout cycling


## Notes

**2026-09-26T20:28:27Z**

Engine: ContainerOrientation (horizontal|vertical|auto), Container.axis(in:), setLayout/setOrientation, orientationChosen; layout command gains horizontal/vertical/auto/h_*/v_*; [layout] accordion-orientation auto|keep. Tests green.

**2026-09-26T20:31:38Z**

VM verified: tall column accordion peeks top/bottom (v_accordion), 'layout accordion horizontal vertical' flips h/v, 'layout auto' back to v, resize width +300 flips auto accordion to h and -300 back. containerAxis now resolves from laid-out rect (minimum sizes count); Finder's min width had held the column tall while the query said h.
