import DinkyLayout
import DinkyPrivate

// What commands ask of the coordinator: tree commands on the focused window's Space, floating, and
// taking in a window dinky moved to another Space.
extension Coordinator {
    /// Whether dinky floats the window; nil for a window it has not classified.
    func isFloating(_ id: WindowID) -> Bool? { placements[id]?.floating }

    /// The tree of the display's current Space, if dinky has one.
    func workspace(on display: Display) -> Workspace? {
        workspaces[SpaceKey(display: display.uuid, space: display.currentSpaceID)]
    }

    /// The container holding a tiled window.
    func container(of id: WindowID) -> Container? {
        placements[id]?.space.flatMap { workspaces[$0]?.container(of: id) }
    }

    /// AeroSpace's name for how a window is laid out: `h_tiles`, `v_tiles`, `h_accordion` or `v_accordion`
    /// from its container, `fullscreen` for dinky's fullscreen, `floating` for any window that is not tiled.
    func layoutName(of id: WindowID) -> String {
        guard let key = placements[id]?.space, let workspace = workspaces[key],
              let container = workspace.container(of: id) else { return "floating" }
        if workspace.fullscreen == id { return "fullscreen" }
        return (container.orientation == .horizontal ? "h_" : "v_") + (container.mode == .accordion ? "accordion" : "tiles")
    }

    /// Runs a command on the tree of a window (the focused one by default), focused in that tree, and applies
    /// what changed. Nil if the window is not tiled.
    func command<T>(on id: WindowID? = nil, _ change: (inout Workspace) -> T) -> T? {
        let id = id ?? focusedWindow
        guard let key = placements[id]?.space else { return nil }
        edit(key) { $0.focus(id) }
        let result = edit(key, change)
        flush()
        return result
    }

    /// Floats a tiled window where it stands, or tiles a floating one beside the focused tile of its Space.
    /// False for a window dinky has not classified.
    @discardableResult
    func setFloating(_ id: WindowID, _ floating: Bool) -> Bool {
        guard let placement = placements[id], let window = model.windows[id] else { return false }
        if let space = placement.space { edit(space) { $0.remove(id) } }
        placements[id] = Placement(floating: floating, space: nil)
        track(window)
        flush()
        return true
    }

    /// Moves a window dinky just moved to another Space into that Space's tree now, rather than on the next event.
    /// macOS leaves keyboard focus with the moved window, so unless we are about to follow it, focus the window
    /// that took its place in the tree it left.
    func windowMoved(_ id: WindowID, refocus: Bool = true) {
        guard var window = model.windows[id] else { return }
        let hadFocus = focusedWindow == id
        let from = placements[id]?.space
        window.spaceID = dinky_window_space_id(id)
        track(window)
        flush()
        guard refocus, hadFocus, let from, let successor = workspaces[from]?.focused, successor != id else { return }
        focus(successor)
    }
}
