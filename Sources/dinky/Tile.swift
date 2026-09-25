import AppKit
import DinkyPrivate

func runTile(_ args: [String]) -> Int32 {
    let displays = dinky_displays()
    guard let main = displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? displays.first,
          let screen = NSScreen.main else {
        fputs("tile: no main display\n", stderr)
        return 1
    }

    let candidates = Set(dinky_space_window_ids(main.currentSpaceID, false).map { $0.uint32Value })
    let info = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
    var windows: [(wid: UInt32, pid: pid_t, owner: String)] = []
    for w in info {
        let wid = w[kCGWindowNumber as String] as? UInt32 ?? 0
        let layer = w[kCGWindowLayer as String] as? Int ?? -1
        let alpha = w[kCGWindowAlpha as String] as? Double ?? 0
        let owner = w[kCGWindowOwnerName as String] as? String ?? ""
        let pid = w[kCGWindowOwnerPID as String] as? pid_t ?? 0
        guard candidates.contains(wid), layer == 0, alpha > 0, owner != "Dock", owner != "WindowServer" else { continue }
        windows.append((wid, pid, owner))
    }
    windows.sort { $0.wid < $1.wid }
    guard !windows.isEmpty else {
        fputs("tile: no windows on current space\n", stderr)
        return 1
    }

    let visible = screen.visibleFrame
    let area = CGRect(x: visible.minX, y: screen.frame.height - (visible.minY + visible.height),
                      width: visible.width, height: visible.height)
    let frames = split(area, windows.count)

    var elements: [AXUIElement?] = []
    for (w, frame) in zip(windows, frames) {
        guard let element = axWindow(pid: w.pid, wid: w.wid) else {
            fputs("tile: \(w.wid) \(w.owner) no AX window\n", stderr)
            elements.append(nil)
            continue
        }
        elements.append(element)
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(w.pid), "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
        var size = frame.size
        var origin = frame.origin
        let sizeValue = AXValueCreate(.cgSize, &size)!
        let originValue = AXValueCreate(.cgPoint, &origin)!
        for (attr, value) in [(kAXSizeAttribute, sizeValue), (kAXPositionAttribute, originValue), (kAXSizeAttribute, sizeValue)] {
            let err = AXUIElementSetAttributeValue(element, attr as CFString, value)
            if err != .success { fputs("tile: \(w.wid) \(w.owner) set \(attr) error \(err.rawValue)\n", stderr) }
        }
    }

    usleep(200_000)
    for ((w, wanted), element) in zip(zip(windows, frames), elements) {
        guard let element else { continue }
        var origin = CGPoint.zero
        var size = CGSize.zero
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success {
            AXValueGetValue(value as! AXValue, .cgPoint, &origin)
        }
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success {
            AXValueGetValue(value as! AXValue, .cgSize, &size)
        }
        let got = CGRect(origin: origin, size: size)
        let ok = abs(got.minX - wanted.minX) <= 2 && abs(got.minY - wanted.minY) <= 2 &&
                 abs(got.maxX - wanted.maxX) <= 2 && abs(got.maxY - wanted.maxY) <= 2
        print("\(w.wid) \(w.owner) want=\(fmt(wanted)) got=\(fmt(got)) \(ok ? "OK" : "DIFF")")
    }
    return 0
}

// Split along the longer side; first count/2 (at least one) windows go to the first half.
private func split(_ rect: CGRect, _ count: Int) -> [CGRect] {
    if count <= 1 { return [rect] }
    let first = max(count / 2, 1)
    let (a, b) = rect.width >= rect.height
        ? rect.divided(atDistance: rect.width / 2, from: .minXEdge)
        : rect.divided(atDistance: rect.height / 2, from: .minYEdge)
    return split(a, first) + split(b, count - first)
}

private func fmt(_ r: CGRect) -> String {
    "\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height))"
}
