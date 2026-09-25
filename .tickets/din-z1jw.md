---
id: din-z1jw
status: open
deps: []
links: []
created: 2026-09-25T09:32:53Z
type: feature
priority: 1
assignee: Mikkel Malmberg
parent: din-eqz3
tags: [foundation, app]
---
# App bundle, signing, Accessibility onboarding, launch at login

Turn the bare executable into dinky.app: Info.plist with LSUIElement, stable signing identity so the Accessibility grant survives rebuilds, first-run flow that explains and opens the Accessibility pane, SMAppService launch at login. Onboarding also offers to turn off the native 'switch to a Space with open windows' setting, with the reason.

## Acceptance Criteria

A rebuilt app keeps its Accessibility grant. First launch shows onboarding until permission is granted. Launch at login works and can be turned off in config.

