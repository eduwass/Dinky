import AppKit
import DinkyPrivate

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

func windowPID(_ wid: UInt32) -> pid_t? {
    let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, wid) as? [[String: Any]] ?? []
    return info.first?[kCGWindowOwnerPID as String] as? pid_t
}

func axWindow(pid: pid_t, wid: UInt32) -> AXUIElement? {
    let app = AXUIElementCreateApplication(pid)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
          let windows = value as? [AXUIElement] else { return nil }
    return windows.first { axWindowID($0) == wid }
}

func axWindowID(_ element: AXUIElement) -> UInt32 {
    var wid: CGWindowID = 0
    return _AXUIElementGetWindow(element, &wid) == .success ? wid : 0
}

private func spaceIndex(_ sid: UInt64) -> String {
    let displays = dinky_displays()
    let main = displays.first { $0.displayID == CGMainDisplayID() } ?? displays.first
    guard let i = main?.spaces.firstIndex(where: { $0.spaceID == sid }) else { return "sid:\(sid)" }
    return String(i + 1)
}

private func currentSpaceID() -> UInt64 {
    let displays = dinky_displays()
    let main = displays.first { $0.displayID == CGMainDisplayID() } ?? displays.first
    return main?.currentSpaceID ?? 0
}

func frontWindowID() -> UInt32 {
    guard let app = NSWorkspace.shared.frontmostApplication else { return 0 }
    var value: CFTypeRef?
    let element = AXUIElementCreateApplication(app.processIdentifier)
    guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success,
          let window = value else { return 0 }
    return axWindowID(window as! AXUIElement)
}

func runFocus(_ args: [String]) -> Int32 {
    guard let first = args.first, let wid = UInt32(first) else {
        fputs("usage: dinky focus <window-id> [--path ax|private]\n", stderr)
        return 64
    }
    var path = "ax"
    if let i = args.firstIndex(of: "--path"), i + 1 < args.count { path = args[i + 1] }
    guard path == "ax" || path == "private" else {
        fputs("focus: unknown path \(path)\n", stderr)
        return 64
    }
    guard let pid = windowPID(wid) else {
        fputs("focus: no window \(wid)\n", stderr)
        return 1
    }

    let before = currentSpaceID()
    print("path=\(path) pid=\(pid) current=\(spaceIndex(before)) window=\(spaceIndex(dinky_window_space_id(wid))) front=\(frontWindowID())")

    if path == "ax" {
        guard let window = axWindow(pid: pid, wid: wid) else {
            fputs("focus: no AX window for \(wid)\n", stderr)
            return 1
        }
        let err = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        if err != .success { fputs("focus: AXRaise error \(err.rawValue)\n", stderr) }
        let activated = NSRunningApplication(processIdentifier: pid)?.activate() ?? false
        if !activated { fputs("focus: activate returned false\n", stderr) }
    } else {
        if !dinky_focus_window_private(pid, wid) { fputs("focus: private focus failed\n", stderr) }
        // yabai follows the private calls with an AX raise; without it the window often stays behind.
        if let window = axWindow(pid: pid, wid: wid) {
            let err = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            if err != .success { fputs("focus: AXRaise error \(err.rawValue)\n", stderr) }
        }
    }

    usleep(300_000)
    let after = currentSpaceID()
    let front = frontWindowID()
    print("after current=\(spaceIndex(after)) front=\(front) \(front == wid ? "hit" : "miss") space \(after == before ? "unchanged" : "changed")")
    return 0
}
