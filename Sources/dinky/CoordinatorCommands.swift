import DinkyLayout
import DinkyPrivate

// What commands ask of the coordinator: tree commands on the focused window's Space, floating, and
// taking in a window dinky moved to another Space.
extension Coordinator {
    /// Whether dinky floats the window; nil for a window it has not classified.
    func isFloating(_ id: WindowID) -> Bool? { placements[id]?.floating }

    /// The layout mode of the container holding a tiled window.
    func mode(of id: WindowID) -> LayoutMode? {
        placements[id]?.space.flatMap { workspaces[$0]?.mode(of: id) }
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
    func windowMoved(_ id: WindowID) {
        guard var window = model.windows[id] else { return }
        window.spaceID = dinky_window_space_id(id)
        track(window)
        flush()
    }
}
