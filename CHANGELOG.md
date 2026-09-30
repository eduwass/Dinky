# Changelog

## Unreleased

- Windows glide to their tiles instead of jumping. Turn it off or change the speed under `[animations]`; it's off while macOS's Reduce Motion is on.
- While you drag a tiled window, dinky outlines the tile it came from and the tile it will swap with (`[drag] placeholders`). The drop now goes to the tile under the pointer rather than under the window's centre.
- A window put into native full screen, or still catching up with a resize, no longer teaches dinky that its app can't shrink, which could leave every window of that app filling the screen.
- `flatten-workspace-tree` puts windows back into the workspace's configured layout: a fixed grid gets its cells back, an accordion workspace becomes an accordion again.
- `move` past the edge of an accordion that fills the workspace takes the window out of it, into a tile beside the accordion, as in AeroSpace.

## 0.4

**Upgrading:** workspaces are now numbered across all displays. `workspaces` is the total rather than a count per display, and `workspaces` inside `[display.<pattern>]` is now a config error. Use `[workspace-to-display]` to put a workspace on a particular display.

### Workspaces

- Workspace numbers stay put when you dock or undock. Each workspace is one Space, on the main display unless `[workspace-to-display]` places it elsewhere.
- dinky removes Spaces it no longer needs instead of letting leftovers pile up.
- Tiled windows keep their layout when their workspace moves to another display.
- `workspace N` goes to whichever display the workspace is on; `workspace prev` and `next` step through the focused display's workspaces.
- Queries, hooks and the menu bar use the new global numbers.

### Layouts

- New `fixed` layout: give a workspace a grid with `[workspace.N]` `columns` and `rows`. New windows fill empty cells without resizing the others; when the grid is full, `expand` adds a column, adds a row, or stacks windows in the last cell.
- `default-tiling = false` leaves workspaces untiled unless a `[workspace.N]` table turns tiling on.
- `dwindle` is accepted as another name for the `tiles` layout.

### Fixes

- Cmd-Tab to Helium and Safari web apps switches Spaces again.
- `workspace-back-and-forth` returns to the workspace you were on, not a Space you swiped past.
