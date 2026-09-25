---
id: din-ecx6
status: open
deps: [din-cc9k]
links: []
created: 2026-09-25T09:32:54Z
type: feature
priority: 1
assignee: Mikkel Malmberg
parent: din-7cqx
tags: [release, recovery]
---
# Enable, disable, restore on quit, crash recovery

Journal original frames and Space membership before dinky first touches a window. Disable and quit cancel queued work and restore frames on still-valid displays. After a crash, reconcile live identities and offer restoration from the journal. Emergency disable binding.

## Acceptance Criteria

Quit puts every window back where it was. Killing dinky and relaunching offers restore and does not touch windows that were reused IDs.

