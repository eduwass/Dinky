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
/// `-` for windows on no Space (such as minimized ones). Sorted by display, workspace, then id.
func listWindows() -> String {
    let displays = dinky_displays()
    let windows = windowList()
    let spaceIDs = dinky_space_ids_for_windows(windows.map { NSNumber(value: $0.id) }).map(\.uint64Value)
    var rows: [(display: Int, workspace: Int, id: UInt32, line: String)] = []
    for (window, sid) in zip(windows, spaceIDs) {
        guard sid != 0 || !window.title.isEmpty else { continue }
        let place = workspace(of: sid, in: displays)
        let f = window.frame
        let line = ["\(window.id)", window.app, window.title, "\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))",
                    place.map { "\($0.workspace + 1)" } ?? "-", place.map { "\($0.display + 1)" } ?? "-"]
            .joined(separator: " | ")
        rows.append((place?.display ?? Int.max, place?.workspace ?? Int.max, window.id, line))
    }
    rows.sort { ($0.display, $0.workspace, $0.id) < ($1.display, $1.workspace, $1.id) }
    return rows.map(\.line).joined(separator: "\n")
}

/// `<display> | <workspace> | <space-id> | <kind>[ | current]`, one line per Space.
func listWorkspaces() -> String {
    var lines: [String] = []
    for (d, display) in dinky_displays().enumerated() {
        for (i, space) in display.spaces.enumerated() {
            let kind = space.isFullscreen ? "fullscreen" : space.isUser ? "user" : "type \(space.type.rawValue)"
            let current = space.spaceID == display.currentSpaceID ? " | current" : ""
            lines.append("\(d + 1) | \(i + 1) | \(space.spaceID) | \(kind)\(current)")
        }
    }
    return lines.joined(separator: "\n")
}

/// `<display> | <display-id> | <uuid> | <x>,<y> <w>x<h>[ | main]`
func listDisplays() -> String {
    dinky_displays().enumerated().map { d, display in
        let f = CGDisplayBounds(display.displayID)
        let main = display.displayID == CGMainDisplayID() ? " | main" : ""
        return "\(d + 1) | \(display.displayID) | \(display.uuid) | \(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))\(main)"
    }.joined(separator: "\n")
}

private func workspace(of sid: UInt64, in displays: [DinkyDisplay]) -> (display: Int, workspace: Int)? {
    for (d, display) in displays.enumerated() {
        if let i = display.spaces.firstIndex(where: { $0.spaceID == sid }) { return (d, i) }
    }
    return nil
}
