---
id: din-xfjb
status: open
deps: [din-5sdy]
links: []
created: 2026-09-25T09:32:54Z
type: chore
priority: 3
assignee: Mikkel Malmberg
parent: din-7cqx
tags: [cleanup]
---
# Remove spike-only switch paths and CLI subcommands

Drop the Tuna and bridged set-current-Space paths, the keys and number experiments, and the velocity override once the CLI over the socket exists. Keep RESULTS.md as the record.

## Acceptance Criteria

switch.m contains only the mimi path; the spike subcommands are gone.

