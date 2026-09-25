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

    /// Runs a command. `window` stands in for the focused window in commands that act on one, for
    /// on-window-detected rules; bindings and the CLI leave it nil.
    static func run(_ command: Command, window: WindowID? = nil) -> Reply {
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
            return moveWindowToWorkspace(target, follow: follow, window: window ?? focusedWindowID())
        case .moveWindowToDisplay(let target, let follow):
            return moveWindowToDisplay(target, follow: follow, window: window ?? focusedWindowID())
        case .focus(let direction, let boundaries, let action):
            return focus(direction, boundaries: boundaries, action: action)
        case .focusMonitor(let target):
            return focusMonitor(target)
        case .layout(let names):
            return layout(names, window: window)
        case .move(let direction):
            return tree("move \(direction)") { $0.move(direction) }
        case .joinWith(let direction):
            return tree("join-with \(direction)") { $0.join(direction) }
        case .resize(let dimension, let delta):
            let axis: Orientation? = switch dimension {
            case .smart: nil
            case .width: .horizontal
            case .height: .vertical
            }
            return tree("resize \(dimension.rawValue) \(delta)") { $0.resize(by: CGFloat(delta), along: axis) }
        case .fullscreen:
            return tree("fullscreen") { $0.toggleFullscreen(); return true }
        case .flattenWorkspaceTree:
            return tree("flatten-workspace-tree") { $0.flatten(); return true }
        case .balanceSizes:
            return tree("balance-sizes") { $0.balanceSizes(); return true }
        case .retile:
            guard let coordinator = AppState.shared.coordinator else { return .error("tiling is not running") }
            coordinator.reconcile()
            return .ok("retiled")
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
        case .listWindows(let query):
            return listWindows(query)
        case .listWorkspaces(let query):
            return .ok(listWorkspaces(query))
        case .listMonitors(let query):
            return .ok(listMonitors(query))
        case .execAndForget(let shell):
            exec(["/bin/sh", "-c", shell])
            return .ok("")
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

    /// The focused display, freshly read, and its current 0-based workspace, or the one it is switching to
    /// so that rapid `workspace next` requests add up. Nil on a full-screen Space.
    private static func focusedWorkspace() -> (Display, Int)? {
        let model = AppState.shared.displays
        model.reconcile()
        guard let display = model.focusedDisplay(),
              let current = display.workspaces.firstIndex(of: targetSpaceID(on: display)) else { return nil }
        return (display, current)
    }

    private static func switchWorkspace(_ target: WorkspaceTarget) -> Reply {
        guard let (display, current) = focusedWorkspace() else { return .error("not on a numbered workspace") }
        let to = index(target, current: current)
        guard display.workspaces.indices.contains(to) else { return .error("no workspace \(to + 1), there are \(display.workspaces.count)") }
        guard to != current else { return .ok("already on workspace \(to + 1)") }
        guard switchSpace(toSpaceID: display.workspaces[to], on: display) else { return .error("switch to workspace \(to + 1) failed") }
        return .ok("workspace \(to + 1)")
    }

    private static func moveWindowToWorkspace(_ target: WorkspaceTarget, follow: Bool, window wid: WindowID) -> Reply {
        guard let (display, current) = focusedWorkspace() else { return .error("not on a numbered workspace") }
        let to = index(target, current: current)
        guard display.workspaces.indices.contains(to) else { return .error("no workspace \(to + 1), there are \(display.workspaces.count)") }
        guard wid != 0 else { return .error("no focused window") }
        guard to != current else { return .ok("window \(wid) is already on workspace \(to + 1)") }
        var ids = [wid]
        let space = display.workspaces[to]
        guard dinky_window_space_id(wid) != space else { return .ok("window \(wid) is already on workspace \(to + 1)") }
        guard dinky_move_windows_to_space(&ids, 1, space) else { return .error("move failed") }
        // The bridged move is asynchronous; follow only once the window is really there.
        guard waitUntil(0.5, { dinky_window_space_id(wid) == space }) else {
            return .error("window \(wid) did not arrive on workspace \(to + 1)")
        }
        AppState.shared.coordinator?.windowMoved(wid, refocus: !follow)
        if follow { switchSpace(toSpaceID: space, on: display) }
        return .ok("moved window \(wid) to workspace \(to + 1)")
    }

    // MARK: Layout tree

    /// Runs a change on the focused window's tree; `change` returns false when there was nothing to do.
    private static func tree(_ name: String, _ change: (inout Workspace) -> Bool) -> Reply {
        guard let coordinator = AppState.shared.coordinator else { return .error("tiling is not running") }
        switch coordinator.command(change) {
        case nil: return .error("\(name): the focused window is not tiled")
        case false?: return .error("\(name): nothing to do")
        case true?: return .ok(name)
        }
    }

    /// Applies the first layout that does not describe the window now, or the first if all do:
    /// floating or tiling for the window, tiles or accordion for its container (tiling it first if it floats).
    private static func layout(_ names: [LayoutName], window: WindowID?) -> Reply {
        guard let coordinator = AppState.shared.coordinator else { return .error("tiling is not running") }
        let id = window ?? coordinator.focusedWindow
        guard let floating = coordinator.isFloating(id) else { return .error("layout: no window dinky manages is focused") }
        let current: [LayoutName] = floating ? [.floating] : [.tiling, coordinator.container(of: id)?.mode == .accordion ? .accordion : .tiles]
        let name = names.first { !current.contains($0) } ?? names[0]
        switch name {
        case .floating, .tiling:
            coordinator.setFloating(id, name == .floating)
        case .tiles, .accordion:
            if floating { coordinator.setFloating(id, false) }
            coordinator.command(on: id) { $0.setMode(name == .accordion ? .accordion : .tiles) }
        }
        return .ok("layout \(name.rawValue)")
    }

    // MARK: Windows

    /// Moves a window to the current Space of the next or previous display (wrapping around), into that
    /// Space's tree. A floating window keeps its offset from the display's corner. Untested with two displays.
    private static func moveWindowToDisplay(_ target: DisplayTarget, follow: Bool, window wid: WindowID) -> Reply {
        let model = AppState.shared.displays
        model.reconcile()
        guard wid != 0, let pid = windowPID(wid), let from = model.display(ofWindow: wid) else { return .error("no focused window") }
        let displays = model.displays
        guard displays.count > 1, let i = displays.firstIndex(of: from) else { return .error("no other display") }
        let n = (i + (target == .next ? 1 : -1) + displays.count) % displays.count
        let to = displays[n], space = to.currentSpaceID
        var ids = [wid]
        guard dinky_move_windows_to_space(&ids, 1, space) else { return .error("move failed") }
        guard waitUntil(0.5, { dinky_window_space_id(wid) == space }) else { return .error("window \(wid) did not arrive on display \(n + 1)") }
        if AppState.shared.coordinator?.isFloating(wid) != false {
            let frame = dinky_window_info(wid).frame
            let origin = CGPoint(x: to.frame.minX + max(0, frame.minX - from.frame.minX),
                                 y: to.frame.minY + max(0, frame.minY - from.frame.minY))
            if let element = axWindow(pid: pid, wid: wid) { setPosition(element, origin) }
        }
        AppState.shared.coordinator?.windowMoved(wid, refocus: !follow)
        if follow { focusWindow(pid: pid, id: wid) }
        return .ok("moved window \(wid) to display \(n + 1)")
    }

    @discardableResult
    private static func setPosition(_ element: AXUIElement, _ origin: CGPoint) -> Bool {
        var origin = origin
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &origin)!) == .success
    }
}

/// The window a command acts on: the coordinator's focused window (the front app's frontmost document window
/// on a visible Space), falling back to the front app's AX key window, which can still be one on another Space.
private func focusedWindowID() -> WindowID {
    if let id = AppState.shared.coordinator?.focusedWindow, id != 0 { return id }
    return frontWindowID()
}
