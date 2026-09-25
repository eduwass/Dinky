---
id: din-5sdy
status: open
deps: [din-g6bk]
links: []
created: 2026-09-25T09:32:53Z
type: feature
priority: 1
assignee: Mikkel Malmberg
parent: din-eqz3
tags: [foundation, cli]
---
# CLI over unix socket

dinky <command> from a shell sends the command to the running app over a unix socket in the user's temp dir and prints the reply. Queries too: dinky list-windows, list-workspaces. The spike's subcommands are replaced by this.

## Acceptance Criteria

dinky workspace 2 switches from a terminal. dinky list-windows prints windows with workspace and display. Running without the app gives a clear error.

