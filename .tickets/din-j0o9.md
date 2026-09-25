---
id: din-j0o9
status: open
deps: [din-5rp2]
links: []
created: 2026-09-25T09:32:53Z
type: feature
priority: 1
assignee: Mikkel Malmberg
parent: din-8wj4
tags: [spaces, displays]
---
# Display and Space model

Per display: UUID, Space list in Mission Control order, current Space, focused display (from the focused window or cursor). Update on display connect, disconnect and arrangement changes. Full-screen Spaces are excluded from workspace numbering.

## Acceptance Criteria

Plugging and unplugging the external display updates the model without restart, and windows on a removed display are reconciled.

