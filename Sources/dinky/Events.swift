import AppKit
import DinkyPrivate

// `dinky debug events` prints the WindowServer event stream with the model's view of each window until
// killed; `dinky debug windows` prints the model's windows and exits. Both run without the app.
func runDebug(_ args: [String]) -> Int32 {
    guard args == ["events"] || args == ["windows"] else {
        fputs("usage: dinky debug events|windows\n", stderr)
        return 64
    }
    let model = WindowModel()
    // SkyLight only delivers notifications while AppKit drains the connection's event port.
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)

    guard model.start() else {
        fputs("debug: could not register for WindowServer notifications\n", stderr)
        return 1
    }

    if args == ["windows"] {
        for window in model.windows.values.sorted(by: { $0.id < $1.id }) { print(describe(window)) }
        return 0
    }

    let clock = DateFormatter()
    clock.dateFormat = "HH:mm:ss.SSS"
    print("watching \(model.windows.count) windows, ctrl-c to stop")
    model.onChange = { event in
        let t = clock.string(from: event.time)
        let kind = name(event.kind)
        var line = "\(t) \(kind.padding(toLength: 14, withPad: " ", startingAt: 0)) \(event.change)"
        if event.pid != 0 { line += " pid=\(event.pid)" }
        if event.spaceID != 0 { line += " space=\(event.spaceID)" }
        if let window = event.window { line += "  " + describe(window) }
        print(line)
        fflush(stdout)
    }
    app.run()
    return 0
}

private func describe(_ w: Window) -> String {
    let f = "\(Int(w.frame.minX)),\(Int(w.frame.minY)) \(Int(w.frame.width))x\(Int(w.frame.height))"
    var flags: [String] = []
    if w.isNormal { flags.append("normal") }
    if !w.isOrderedIn { flags.append("hidden") }
    if w.isMinimized { flags.append("minimized") }
    if !w.isDocument { flags.append("non-document") }
    return "wid=\(w.id) pid=\(w.pid) space=\(w.spaceID) level=\(w.level) radius=\(w.cornerRadius) \(f) [\(flags.joined(separator: ","))] \(w.appName ?? "?") \(w.bundleID ?? "")"
}

private func name(_ kind: DinkyEventKind) -> String {
    switch kind {
    case .windowUpdate: "update"
    case .windowClose: "close"
    case .windowMove: "move"
    case .windowResize: "resize"
    case .windowReorder: "reorder"
    case .windowLevel: "level"
    case .windowUnhide: "unhide"
    case .windowHide: "hide"
    case .windowTitle: "title"
    case .windowCreate: "create"
    case .windowDestroy: "destroy"
    case .spaceCreated: "space-created"
    case .spaceDestroyed: "space-destroyed"
    case .spaceChange: "space-change"
    case .frontApp: "front-app"
    @unknown default: "\(kind.rawValue)"
    }
}
