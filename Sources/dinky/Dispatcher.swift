import AppKit
import DinkyCommands
import DinkyConfig
import DinkyLayout
import DinkyPrivate

/// What a command answers: a short line for the CLI, and whether it worked.
struct Reply {
    var ok: Bool
    var text: String

    static func ok(_ text: String) -> Reply { Reply(ok: true, text: text) }
    static func error(_ text: String) -> Reply { Reply(ok: false, text: text) }
}

// Runs commands from bindings, the CLI and the menu against what exists today. Main thread only.
// Workspace commands act on the focused display.
enum Dispatcher {
    static func run(_ line: String) -> Reply {
        do {
            return run(try Command.parse(line))
        } catch {
            return .error(error.description)
        }
    }

    static func run(_ command: Command) -> Reply {
        switch command {
        case .workspace(let target):
            return switchWorkspace(target)
        case .workspaceBackAndForth:
            let model = AppState.shared.displays
            guard let display = model.focusedDisplay(), let previous = model.previousWorkspace(on: display) else {
                return .error("no previous workspace")
            }
            return switchWorkspace(.number(previous + 1))
        case .moveWindowToWorkspace(let target, let follow):
            return moveWindowToWorkspace(target, follow: follow)
        case .moveWindowToDisplay(let target, let follow):
            return moveWindowToDisplay(target, follow: follow)
        case .focus(let direction):
            return focus(direction)
        case .layout([.tiles]):
            // The spike's split tiling until the tree is wired (din-ftk4 and friends).
            return runTile([]) == 0 ? .ok("tiled") : .error("nothing to tile")
        case .move, .joinWith, .resize, .layout, .fullscreen, .flattenWorkspaceTree:
            return .error("not yet: the layout tree is not wired to windows")
        case .mode(let name):
            guard AppState.shared.config.modes[name] != nil else { return .error("no mode '\(name)' in the config") }
            AppState.shared.hotkeys.setMode(name)
            return .ok("mode \(name)")
        case .reloadConfig:
            if let error = AppState.shared.loadConfig() { return .error("config: \(error)") }
            return .ok("reloaded \(Config.userConfigURL.path)")
        case .enable(let toggle):
            let on = toggle == .toggle ? !AppState.shared.enabled : toggle == .on
            AppState.shared.setEnabled(on)
            return .ok(on ? "enabled" : "disabled")
        case .listWindows:
            return .ok(listWindows())
        case .listWorkspaces:
            return .ok(listWorkspaces())
        case .listDisplays:
            return .ok(listDisplays())
        }
    }

    // MARK: Workspaces

    /// 0-based index for a target, relative to the current Space. No wrap-around.
    private static func index(_ target: WorkspaceTarget, current: Int) -> Int {
        switch target {
        case .number(let n): return n - 1
        case .prev: return current - 1
        case .next: return current + 1
        }
    }

    /// The focused display, freshly read, and its current 0-based workspace. Nil on a full-screen Space.
    private static func focusedWorkspace() -> (Display, Int)? {
        let model = AppState.shared.displays
        model.reconcile()
        guard let display = model.focusedDisplay(), let current = display.currentWorkspace else { return nil }
        return (display, current)
    }

    private static func switchWorkspace(_ target: WorkspaceTarget) -> Reply {
        guard let (display, current) = focusedWorkspace() else { return .error("not on a numbered workspace") }
        let to = index(target, current: current)
        guard display.workspaces.indices.contains(to) else { return .error("no workspace \(to + 1), there are \(display.workspaces.count)") }
        guard to != current else { return .ok("already on workspace \(to + 1)") }
        guard switchSpace(to: to, on: display) else { return .error("switch to workspace \(to + 1) failed") }
        return .ok("workspace \(to + 1)")
    }

    private static func moveWindowToWorkspace(_ target: WorkspaceTarget, follow: Bool) -> Reply {
        guard let (display, current) = focusedWorkspace() else { return .error("not on a numbered workspace") }
        let to = index(target, current: current)
        guard display.workspaces.indices.contains(to) else { return .error("no workspace \(to + 1), there are \(display.workspaces.count)") }
        let wid = frontWindowID()
        guard wid != 0 else { return .error("no focused window") }
        guard to != current else { return .ok("window \(wid) is already on workspace \(to + 1)") }
        var ids = [wid]
        guard dinky_move_windows_to_space(&ids, 1, display.workspaces[to]) else { return .error("move failed") }
        if follow { _ = switchWorkspace(.number(to + 1)) }
        return .ok("moved window \(wid) to workspace \(to + 1)")
    }

    // MARK: Windows

    /// Moves the focused window onto the next or previous display's current Space by placing it there with
    /// AX, at the same offset from the display's corner. Untested with more than one display.
    private static func moveWindowToDisplay(_ target: DisplayTarget, follow: Bool) -> Reply {
        let displays = dinky_displays()
        let wid = frontWindowID()
        guard wid != 0, let window = windowList().first(where: { $0.id == wid }) else { return .error("no focused window") }
        guard displays.count > 1 else { return .error("only one display") }
        let from = displays.firstIndex { CGDisplayBounds($0.displayID).contains(window.frame.origin) } ?? 0
        let to = (from + (target == .next ? 1 : -1) + displays.count) % displays.count
        let fromBounds = CGDisplayBounds(displays[from].displayID)
        let toBounds = CGDisplayBounds(displays[to].displayID)
        let origin = CGPoint(x: toBounds.minX + max(0, window.frame.minX - fromBounds.minX),
                             y: toBounds.minY + max(0, window.frame.minY - fromBounds.minY))
        guard let element = axWindow(pid: window.pid, wid: wid), setPosition(element, origin) else {
            return .error("could not move window \(wid)")
        }
        if follow { focusWindow(window) }
        return .ok("moved window \(wid) to display \(to + 1)")
    }

    /// The nearest window on the current Space whose centre lies in the direction, by distance between centres.
    private static func focus(_ direction: Direction) -> Reply {
        guard let main = mainDisplay() else { return .error("no display") }
        let onSpace = Set(dinky_space_window_ids(main.currentSpaceID, false).map(\.uint32Value))
        let windows = windowList().filter { onSpace.contains($0.id) }
        guard let front = windows.first(where: { $0.id == frontWindowID() }) else { return .error("no focused window") }
        let from = CGPoint(x: front.frame.midX, y: front.frame.midY)
        let candidates = windows.filter { w in
            let dx = w.frame.midX - from.x, dy = w.frame.midY - from.y
            switch direction {
            case .left: return dx < 0 && abs(dx) >= abs(dy)
            case .right: return dx > 0 && abs(dx) >= abs(dy)
            case .up: return dy < 0 && abs(dy) >= abs(dx)
            case .down: return dy > 0 && abs(dy) >= abs(dx)
            }
        }
        guard let next = candidates.min(by: { hypot($0.frame.midX - from.x, $0.frame.midY - from.y)
                                              < hypot($1.frame.midX - from.x, $1.frame.midY - from.y) }) else {
            return .error("no window \(direction)")
        }
        focusWindow(next)
        return .ok("focused window \(next.id) \(next.app)")
    }

    private static func focusWindow(_ window: WindowInfo) {
        if let element = axWindow(pid: window.pid, wid: window.id) {
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        }
        NSRunningApplication(processIdentifier: window.pid)?.activate()
    }

    private static func setPosition(_ element: AXUIElement, _ origin: CGPoint) -> Bool {
        var origin = origin
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &origin)!) == .success
    }
}
