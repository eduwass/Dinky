import DinkyLayout

// The one command vocabulary shared by key bindings, the CLI and the menu bar.
// Names and arguments follow AeroSpace (MIT, github.com/nikitabobko/AeroSpace) where dinky has the feature.

public enum Command: Equatable, Sendable {
    case workspace(WorkspaceTarget)
    case workspaceBackAndForth
    case moveWindowToWorkspace(WorkspaceTarget, follow: Bool)
    case moveWindowToDisplay(DisplayTarget, follow: Bool)
    /// Focus the neighbour in a direction. `boundaries` says where the search stops, `action` what happens there.
    case focus(Direction, boundaries: FocusBoundaries = .workspace, action: BoundariesAction = .stop)
    case focusMonitor(MonitorTarget)
    case move(Direction)
    case joinWith(Direction)
    case resize(ResizeDimension, by: Int)
    /// One layout, or several to cycle through: the first that does not describe the current state wins,
    /// so `layout floating tiling` toggles between the two.
    case layout([LayoutName])
    case fullscreen
    case flattenWorkspaceTree
    case balanceSizes
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

/// Where `focus` looks: the focused workspace's tree, or on across displays up to their outer frame.
public enum FocusBoundaries: String, Equatable, Sendable {
    case workspace
    case allMonitorsOuterFrame = "all-monitors-outer-frame"
}

/// What `focus` does at its boundary: nothing and succeed, fail, or wrap to the far side of the
/// workspace or of all the displays.
public enum BoundariesAction: String, Equatable, Sendable {
    case stop, fail
    case wrapAroundTheWorkspace = "wrap-around-the-workspace"
    case wrapAroundAllMonitors = "wrap-around-all-monitors"
}

/// A display relative to the focused one: in a direction by frame, or next and previous in display order.
public enum MonitorTarget: String, Equatable, Sendable {
    case left, right, up, down, next, prev

    /// The direction for left, right, up and down; nil for next and prev.
    public var direction: Direction? { Direction(rawValue) }
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
