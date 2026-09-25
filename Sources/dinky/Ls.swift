import AppKit
import DinkyPrivate

func runLs(_ args: [String]) -> Int32 {
    let displays = dinky_displays()
    let main = displays.first { $0.displayID == CGMainDisplayID() } ?? displays.first

    print("displays")
    for display in displays {
        let tag = display === main ? " (main)" : ""
        print("  \(display.uuid) id=\(display.displayID)\(tag)")
        for (i, space) in display.spaces.enumerated() {
            let current = space.spaceID == display.currentSpaceID ? "*" : " "
            let kind = space.isFullscreen ? " fullscreen" : space.isUser ? "" : " type=\(space.type.rawValue)"
            print("   \(current)\(pad(String(i + 1), 3)) space=\(space.spaceID)\(kind)")
        }
    }

    guard let info = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
        fputs("ls: CGWindowListCopyWindowInfo failed\n", stderr)
        return 1
    }

    print("windows")
    print("  \(pad("id", 7)) \(pad("pid", 6)) \(pad("space", 8)) \(pad("frame", 22)) app / title")
    for w in info {
        let layer = w[kCGWindowLayer as String] as? Int ?? -1
        let alpha = w[kCGWindowAlpha as String] as? Double ?? 0
        let owner = w[kCGWindowOwnerName as String] as? String ?? ""
        let title = w[kCGWindowName as String] as? String ?? ""
        let bounds = w[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
        let frame = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)

        guard layer == 0, alpha > 0, owner != "Dock", owner != "WindowServer" else { continue }
        guard !title.isEmpty || (frame.width > 40 && frame.height > 40) else { continue }

        let wid = w[kCGWindowNumber as String] as? UInt32 ?? 0
        let pid = w[kCGWindowOwnerPID as String] as? Int32 ?? 0
        let sid = dinky_window_space_id(wid)
        guard sid != 0 || !title.isEmpty else { continue }
        let space: String
        if sid == 0 {
            space = "-"
        } else if let i = main?.spaces.firstIndex(where: { $0.spaceID == sid }) {
            space = String(i + 1)
        } else {
            space = "sid:\(sid)"
        }
        let f = "\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))"
        print("  \(pad(String(wid), 7)) \(pad(String(pid), 6)) \(pad(space, 8)) \(pad(f, 22)) \(owner) / \(title)")
    }
    return 0
}

private func pad(_ s: String, _ width: Int) -> String {
    s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
}
