import CoreGraphics

/// One Space's tiling state: the tree, focus, fullscreen and the geometry settings used to lay it out.
public struct Workspace: Equatable, Sendable {
    /// The Space's visible rect, top-left origin.
    public var bounds: CGRect
    public var gaps: Gaps
    public var accordionPadding: CGFloat
    /// The tree. The root is always a container, possibly empty.
    public internal(set) var root: Container
    /// The focused window, if any.
    public internal(set) var focused: WindowID?
    /// The window shown fullscreen over the tree, if any.
    public internal(set) var fullscreen: WindowID?

    /// An empty workspace whose root uses `mode`.
    public init(bounds: CGRect, gaps: Gaps = .zero, accordionPadding: CGFloat = 30, mode: LayoutMode = .tiles) {
        self.bounds = bounds
        self.gaps = gaps
        self.accordionPadding = accordionPadding
        self.root = Container(.horizontal, mode)
    }

    /// All windows in tree order.
    public var windows: [WindowID] { Node.container(root).windows }

    /// Whether the window is tiled here.
    public func contains(_ id: WindowID) -> Bool { root.path(of: id) != nil }

    /// Insert a window beside the focused one and focus it. The focused leaf is split along its longer side
    /// (a square splits side by side); if its parent already runs that way, or is an accordion, it joins as a sibling.
    public mutating func insert(_ id: WindowID) {
        guard !contains(id) else { return }
        guard let focused, let path = root.path(of: focused) else {
            root.insert(.window(id), at: root.children.count)
            return focus(id)
        }
        let leaf = root.rect(at: path, in: gaps.inset(bounds))
        let axis: Orientation = leaf.width >= leaf.height ? .horizontal : .vertical
        let parentPath = Array(path.dropLast()), index = path.last!
        root.modify(at: parentPath) { parent in
            if parent.children.count == 1 { parent.orientation = axis }
            if parent.orientation == axis || parent.mode == .accordion {
                parent.insert(.window(id), at: index + 1)
            } else {
                parent.replace(at: index, with: .container(Container(axis, .tiles, [.window(focused), .window(id)])))
            }
        }
        focus(id)
    }

    /// Remove a window. Its share goes to its siblings, redundant containers collapse.
    /// If it was focused, focus moves to the window that took its place.
    public mutating func remove(_ id: WindowID) {
        guard let path = root.path(of: id) else { return }
        root.modify(at: Array(path.dropLast())) { $0.remove(at: path.last!) }
        normalize()
        if fullscreen == id { fullscreen = nil }
        if focused == id {
            focused = nil
            if let next = mostRecentWindow(in: root) { focus(next) }
        }
    }

    /// Collapse all nesting into the root, keeping window order, with equal ratios.
    public mutating func flatten() {
        let windows = windows
        root = Container(root.orientation, root.mode, windows.map(Node.window))
        if let focused { focus(focused) }
    }

    /// Focus a window and mark it most recent along its path, so accordions show it on top.
    public mutating func focus(_ id: WindowID) {
        guard let path = root.path(of: id) else { return }
        focused = id
        for depth in path.indices {
            root.modify(at: Array(path.prefix(depth))) { $0.active = path[depth] }
        }
    }

    /// Focus the neighbour in `direction`. Returns false when there is none.
    @discardableResult
    public mutating func focus(_ direction: Direction) -> Bool {
        guard let focused, let target = neighbor(of: focused, direction) else { return false }
        focus(target)
        return true
    }

    /// Set the layout mode of the focused window's parent container.
    public mutating func setMode(_ mode: LayoutMode) {
        guard let focused, let path = root.path(of: focused) else { return }
        root.modify(at: Array(path.dropLast())) { $0.mode = mode }
        normalize()
    }

    /// Toggle fullscreen for the focused window. The tree is not changed.
    public mutating func toggleFullscreen() {
        fullscreen = fullscreen == nil ? focused : nil
    }

    /// Frames and stacking for every window. A fullscreen window covers the bounds minus outer gaps and comes first.
    public func layout() -> Layout {
        var result = tiledLayout()
        if let fullscreen, contains(fullscreen) {
            result.frames[fullscreen] = gaps.inset(bounds)
            result.order = [fullscreen] + result.order.filter { $0 != fullscreen }
        }
        return result
    }

    /// The layout ignoring fullscreen, used for geometry questions.
    func tiledLayout() -> Layout {
        var result = Layout()
        root.layout(in: gaps.inset(bounds), gap: gaps.inner, padding: accordionPadding, into: &result)
        return result
    }

    /// Tidy the tree after an edit, and unwrap a root whose only child is a container.
    mutating func normalize() {
        root.normalize()
        if root.children.count == 1, case .container(let only) = root.children[0] { root = only }
    }

    /// The window reached by following active children down from `container`.
    func mostRecentWindow(in container: Container) -> WindowID? {
        guard !container.children.isEmpty else { return nil }
        switch container.children[container.activeIndex] {
        case .window(let id): return id
        case .container(let c): return mostRecentWindow(in: c)
        }
    }
}
