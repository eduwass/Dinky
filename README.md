# Dinky

A tiling window manager for macOS that leaves System Integrity Protection on.

Workspaces are native Spaces, switched in about 70 ms with the same Dock gesture a trackpad sends. Windows tile automatically as they open, with an accordion mode, focus borders, a TOML config in AeroSpace's dialect, and a `dinky` command line for scripts and bars. Nothing is injected into the Dock and SIP stays enabled, at the cost of a few private SkyLight calls that may need attention on each macOS release.

Status: early, in daily use by its author on macOS 27. Expect rough edges.

## Install

```
git clone https://github.com/mikker/Dinky.git
cd Dinky
just install     # builds and signs build/dinky.app, symlinks the CLI into ~/.local/bin
open build/dinky.app
```

Signing uses the author's development identity by default; set `IDENTITY` for your own. On first run the app asks for Accessibility and offers to turn off the macOS setting that makes Cmd-Tab switch Spaces slowly. `dinky doctor` checks the rest.

## More

The [manual](docs/manual.md) covers configuration, every command, the bar integration, and the known limits. [PLAN.md](PLAN.md) and [RESULTS.md](RESULTS.md) record the design decisions and what was measured where.

Approaches were studied from [yabai](https://github.com/asmvik/yabai), [mimi](https://github.com/y3owk1n/mimi), [AeroSpace](https://github.com/nikitabobko/AeroSpace) and [JankyBorders](https://github.com/FelixKratz/JankyBorders); see the manual's credits. No license has been chosen yet.
