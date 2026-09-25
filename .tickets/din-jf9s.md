---
id: din-jf9s
status: open
deps: []
links: []
created: 2026-09-25T09:32:53Z
type: feature
priority: 1
assignee: Mikkel Malmberg
parent: din-eqz3
tags: [foundation, config]
---
# Config: TOML schema, loading, validation, auto reload

~/.config/dinky/dinky.toml parsed with TOMLDecoder into a typed Config. Keys per PLAN.md config draft. Unknown keys and bad values produce a readable error shown in the menu bar and the log, and the previous config stays active. Watch the file and reload; also reload-config command.

## Acceptance Criteria

The draft config in PLAN.md loads. A typo in a key name is reported with the line. Editing the file applies within a second without restart.

