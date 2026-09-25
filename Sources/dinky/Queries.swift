import AppKit
import DinkyPrivate

// The list-* queries, and the window list they and the dispatcher share.
// Output is one line per item, fields separated by " | " as AeroSpace prints them.

struct WindowInfo {
    let id: UInt32
    let pid: pid_t
    let app: String
    let title: String
    /// Global coordinates, top-left origin.
    let frame: CGRect
}

/// Normal windows on any Space, front to back, filtered like the spike's `ls`.
func windowList() -> [WindowInfo] {
    let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    return info.compactMap { w in
        let bounds = w[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
        let window = WindowInfo(
            id: w[kCGWindowNumber as String] as? UInt32 ?? 0,
            pid: w[kCGWindowOwnerPID as String] as? pid_t ?? 0,
            app: w[kCGWindowOwnerName as String] as? String ?? "",
            title: w[kCGWindowName as String] as? String ?? "",
            frame: CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0))
        guard w[kCGWindowLayer as String] as? Int == 0, (w[kCGWindowAlpha as String] as? Double ?? 0) > 0,
              window.app != "Dock", window.app != "WindowServer",
              !window.title.isEmpty || (window.frame.width > 40 && window.frame.height > 40) else { return nil }
        return window
    }
}

/// `<id> | <app> | <title> | <x>,<y> <w>x<h> | <workspace> | <display>`, workspace and display 1-based,
/// `-` for windows on no workspace (minimized ones, full-screen Spaces). Sorted by display, workspace, then id.
func listWindows() -> String {
    let displays = freshDisplays()
    let windows = windowList()
    let spaceIDs = dinky_space_ids_for_windows(windows.map { NSNumber(value: $0.id) }).map(\.uint64Value)
    var rows: [(display: Int, workspace: Int, id: UInt32, line: String)] = []
    for (window, sid) in zip(windows, spaceIDs) {
        guard sid != 0 || !window.title.isEmpty else { continue }
        let d = displays.firstIndex { $0.spaces.contains(sid) }
        let w = d.flatMap { displays[$0].workspaces.firstIndex(of: sid) }
        let f = window.frame
        let line = ["\(window.id)", window.app, window.title, "\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))",
                    w.map { "\($0 + 1)" } ?? "-", d.map { "\($0 + 1)" } ?? "-"]
            .joined(separator: " | ")
        rows.append((d ?? Int.max, w ?? Int.max, window.id, line))
    }
    rows.sort { ($0.display, $0.workspace, $0.id) < ($1.display, $1.workspace, $1.id) }
    return rows.map(\.line).joined(separator: "\n")
}

/// `<display> | <workspace> | <space-id> | <kind>[ | *]`, one line per Space in Mission Control order.
/// Full-screen Spaces have no workspace number (`-`); `*` marks each display's current Space.
func listWorkspaces() -> String {
    var lines: [String] = []
    for (d, display) in freshDisplays().enumerated() {
        for sid in display.spaces {
            let workspace = display.workspaces.firstIndex(of: sid)
            let current = sid == display.currentSpaceID ? " | *" : ""
            lines.append("\(d + 1) | \(workspace.map { "\($0 + 1)" } ?? "-") | \(sid) | \(workspace == nil ? "fullscreen" : "user")\(current)")
        }
    }
    return lines.joined(separator: "\n")
}

/// `<display> | <display-id> | <uuid> | <x>,<y> <w>x<h>[ | main][ | focused]`, frames in global CG coordinates.
func listDisplays() -> String {
    let displays = freshDisplays()
    let focused = AppState.shared.displays.focusedDisplay()?.uuid
    return displays.enumerated().map { d, display in
        let f = display.frame
        let main = display.isMain ? " | main" : ""
        let focus = display.uuid == focused ? " | focused" : ""
        return "\(d + 1) | \(display.id) | \(display.uuid) | \(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))\(main)\(focus)"
    }.joined(separator: "\n")
}

private func freshDisplays() -> [Display] {
    let model = AppState.shared.displays
    model.reconcile()
    return model.displays
}
