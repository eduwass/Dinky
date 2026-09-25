import AppKit
import DinkyConfig
import DinkyLayout
import DinkyPrivate

// `dinky tile`: asks the running app to re-tile. Without the app, `dinky tile [--gap N] [--accordion]` tiles
// the normal windows on the main display's current Space once, through the layout engine and the frame
// applier, and prints the readback.
func runTile(_ args: [String]) -> Int32 {
    if let reply = sendToApp("retile") {
        print(reply.text)
        return reply.ok ? 0 : 1
    }
    let displays = dinky_displays()
    guard let main = displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? displays.first,
          let screen = NSScreen.main else {
        fputs("tile: no main display\n", stderr)
        return 1
    }
    let windows = tileableWindows(onSpace: main.currentSpaceID)
    guard !windows.isEmpty else {
        fputs("tile: no windows on current space\n", stderr)
        return 1
    }

    let config = Config.default
    var gaps = DinkyLayout.Gaps(config.gaps)
    if let i = args.firstIndex(of: "--gap"), i + 1 < args.count, let gap = Double(args[i + 1]) {
        gaps = DinkyLayout.Gaps(all: CGFloat(gap))
    }
    let visible = screen.visibleFrame
    let area = CGRect(x: visible.minX, y: screen.frame.height - visible.maxY, width: visible.width, height: visible.height)
    var workspace = Workspace(bounds: area, gaps: gaps, accordionPadding: CGFloat(config.layout.accordionPadding),
                              mode: args.contains("--accordion") ? .accordion : .tiles)
    for window in windows { workspace.insert(window.id) }

    let applier = FrameApplier()
    let done = DispatchSemaphore(value: 0)
    var results: [FrameResult] = []
    applier.apply(workspace.layout(), pids: Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.pid) })) {
        results = $0
        done.signal()
    }
    done.wait()

    let owners = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.owner) })
    for result in results.sorted(by: { $0.job.id < $1.job.id }) {
        let id = result.job.id
        let got = result.got.map(fmt) ?? "unreadable"
        let notes = (result.written ? "" : " in-place") + (result.retried ? " retried" : "")
        print("\(id) \(owners[id]!) want=\(fmt(result.job.frame)) got=\(got) \(result.matched ? "OK" : "DIFF")\(notes)")
    }
    for (id, size) in applier.minimumSizes.sorted(by: { $0.key < $1.key }) {
        print("\(id) \(owners[id]!) minimum=\(Int(size.width))x\(Int(size.height))")
    }
    return 0
}

// Normal windows on the Space, by window id so insertion order is stable.
private func tileableWindows(onSpace spaceID: UInt64) -> [(id: WindowID, pid: pid_t, owner: String)] {
    let candidates = Set(dinky_space_window_ids(spaceID, false).map { $0.uint32Value })
    let info = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
    return info.compactMap { w -> (WindowID, pid_t, String)? in
        let id = w[kCGWindowNumber as String] as? WindowID ?? 0
        let layer = w[kCGWindowLayer as String] as? Int ?? -1
        let alpha = w[kCGWindowAlpha as String] as? Double ?? 0
        let owner = w[kCGWindowOwnerName as String] as? String ?? ""
        let pid = w[kCGWindowOwnerPID as String] as? pid_t ?? 0
        guard candidates.contains(id), layer == 0, alpha > 0, owner != "Dock", owner != "WindowServer" else { return nil }
        return (id, pid, owner)
    }.sorted { $0.0 < $1.0 }
}

private func fmt(_ r: CGRect) -> String {
    "\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height))"
}
