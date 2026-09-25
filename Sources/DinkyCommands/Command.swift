import DinkyLayout

// The one command vocabulary shared by key bindings, the CLI and the menu bar.
// Names and arguments follow AeroSpace (MIT, github.com/nikitabobko/AeroSpace) where dinky has the feature.

public enum Command: Equatable, Sendable {
    case workspace(WorkspaceTarget)
    case workspaceBackAndForth
    case moveWindowToWorkspace(WorkspaceTarget, follow: Bool)
    case moveWindowToDisplay(DisplayTarget, follow: Bool)
    case focus(Direction)
    case move(Direction)
    case joinWith(Direction)
    case resize(ResizeDimension, by: Int)
    /// One layout, or several to cycle through: the first that does not describe the current state wins,
    /// so `layout floating tiling` toggles between the two.
    case layout([LayoutName])
    case fullscreen
    case flattenWorkspaceTree
    case retile
    case mode(String)
    case reloadConfig
    case enable(Toggle)
    case listWindows(WindowQuery)
    case listWorkspaces(WorkspaceQuery)
    case listMonitors(MonitorQuery)
    /// Shell text run with `/bin/sh -c`, not waited for.
    case execAndForget(String)
}

/// A 1-based workspace number on the focused display, or its neighbour.
public enum WorkspaceTarget: Equatable, Sendable {
    case number(Int)
    case prev, next
}

public enum DisplayTarget: String, Equatable, Sendable {
    case prev, next
}

public enum ResizeDimension: String, Equatable, Sendable {
    case smart, width, height
}

public enum LayoutName: String, Equatable, Sendable {
    case tiles, accordion, floating, tiling
}

public enum Toggle: String, Equatable, Sendable {
    case on, off, toggle
}

extension Direction {
    init?(_ word: String) {
        switch word {
        case "left": self = .left
        case "right": self = .right
        case "up": self = .up
        case "down": self = .down
        default: return nil
        }
    }
}
