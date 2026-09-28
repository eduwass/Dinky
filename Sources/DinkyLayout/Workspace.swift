import CoreGraphics

/// One Space's tiling state: the tree, focus, fullscreen and the geometry settings used to lay it out.
public struct Workspace: Equatable, Sendable {
    /// The Space's visible rect, top-left origin.
    public var bounds: CGRect
    public var gaps: Gaps
    public var accordionPadding: CGFloat
    /// Whether a container switching to accordion follows its longer side (`auto`), unless a `layout` command
    /// chose its orientation.
    public var autoOrientAccordions: Bool
    /// The tree. The root is always a container, possibly empty.
    public internal(set) var root: Container
    /// The focused window, if any.
    public internal(set) var focused: WindowID?
    /// The window shown fullscreen over the tree, if any. Focusing another window or any layout command ends it.
    public internal(set) var fullscreen: WindowID?
    /// Sizes windows refused to go below. Tiles grow to them when their siblings can give the space.
    public var minimumSizes: [WindowID: CGSize] = [:]

    /// An empty workspace whose root uses `mode`. An accordion root with `autoOrientAccordions` starts `auto`,
    /// as a container switched to accordion would, so it runs top to bottom on a tall display.
    public init(bounds: CGRect, gaps: Gaps = .zero, accordionPadding: CGFloat = 30, autoOrientAccordions: Bool = false,
                mode: LayoutMode = .tiles) {
        self.bounds = bounds
        self.gaps = gaps
        self.accordionPadding = accordionPadding
        self.autoOrientAccordions = autoOrientAccordions
        self.root = Container(mode == .accordion && autoOrientAccordions ? .auto : .horizontal, mode)
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
        let joins = axisOfContainer(at: parentPath) == axis || root.container(at: parentPath).children.count == 1
        root.modify(at: parentPath) { parent in
            if parent.children.count == 1, parent.orientation != .auto { parent.orientation = ContainerOrientation(axis) }
            if joins || parent.mode == .accordion {
                parent.insert(.window(id), at: index + 1)
            } else {
                parent.replace(at: index, with: .container(Container(ContainerOrientation(axis), .tiles, [.window(focused), .window(id)])))
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
            if let next = root.mostRecentWindow { focus(next) }
        }
    }

    /// Put `new` in `old`'s place, keeping its size, focus and fullscreen: another tab of the same native tab group
    /// became the one shown. Does nothing if `old` is not here or `new` already is.
    public mutating func replace(_ old: WindowID, with new: WindowID) {
        guard let path = root.path(of: old), !contains(new) else { return }
        root.modify(at: Array(path.dropLast())) { $0.replace(at: path.last!, with: .window(new)) }
        if focused == old { focused = new }
        if fullscreen == old { fullscreen = new }
        minimumSizes[old] = nil
    }

    /// Collapse all nesting into the root, keeping window order, with equal ratios.
    public mutating func flatten() {
        fullscreen = nil
        let windows = windows
        root = Container(root.orientation, root.mode, windows.map(Node.window))
        if let focused { focus(focused) }
    }

    /// Focus a window and mark it most recent along its path, so accordions show it on top.
    /// Ends fullscreen unless it is the fullscreen window.
    public mutating func focus(_ id: WindowID) {
        guard let path = root.path(of: id) else { return }
        focused = id
        if fullscreen != id { fullscreen = nil }
        for depth in path.indices {
            root.modify(at: Array(path.prefix(depth))) { $0.active = path[depth] }
        }
    }

    /// Focus the neighbour in `direction`. At the edge, `wrapping` focuses the window at the opposite edge
    /// instead. Returns false when there is nothing to focus.
    @discardableResult
    public mutating func focus(_ direction: Direction, wrapping: Bool = false) -> Bool {
        guard let focused,
              let target = neighbor(of: focused, direction) ?? (wrapping ? edgeWindow(direction.opposite) : nil),
              target != focused else { return false }
        focus(target)
        return true
    }

    /// The window snapped to the `side` edge: containers along that axis give their first or last child,
    /// the others their most recently focused one. Adapted from AeroSpace's findLeafWindowRecursive(snappedTo:).
    public func edgeWindow(_ side: Direction) -> WindowID? {
        var container = root, rect = gaps.inset(bounds)
        while !container.children.isEmpty {
            let index = container.axis(in: rect) != side.orientation ? container.activeIndex
                : side.isForward ? container.children.count - 1 : 0
            switch container.children[index] {
            case .window(let id): return id
            case .container(let c): (container, rect) = (c, container.rect(at: [index], in: rect))
            }
        }
        return nil
    }

    /// Give every container in the tree equal ratios.
    public mutating func balanceSizes() {
        fullscreen = nil
        root.balance()
    }

    /// The window's parent container, nil if the window is not here.
    public func container(of id: WindowID) -> Container? {
        root.path(of: id).map { root.container(at: Array($0.dropLast())) }
    }

    /// The axis of the window's parent container, `auto` resolved, nil if the window is not here.
    public func containerAxis(of id: WindowID) -> Orientation? {
        root.path(of: id).map { axisOfContainer(at: Array($0.dropLast())) }
    }

    /// The axis the container at `path` runs along now, `auto` resolved from the rectangle it is laid out in
    /// (its windows' frames together), so minimum sizes count as they do on screen.
    func axisOfContainer(at path: [Int]) -> Orientation {
        let container = root.container(at: path), frames = tiledLayout().frames
        let rect = Node.container(container).windows.compactMap { frames[$0] }.reduce(CGRect.null) { $0.union($1) }
        return container.axis(in: rect.isNull ? gaps.inset(bounds) : rect)
    }

    /// Set the layout mode of the focused window's parent container. Ratios are kept, so tiles come back as they were.
    public mutating func setMode(_ mode: LayoutMode) { setLayout(mode, nil) }

    /// Set the orientation of the focused window's parent container, and remember that it was chosen.
    public mutating func setOrientation(_ orientation: ContainerOrientation) { setLayout(nil, orientation) }

    /// Set the mode, the orientation or both of the focused window's parent container, then tidy the tree once,
    /// so the container is not merged into its parent halfway. With `autoOrientAccordions`, a container becoming
    /// an accordion turns `auto` unless a command chose its orientation.
    public mutating func setLayout(_ mode: LayoutMode?, _ orientation: ContainerOrientation?) {
        fullscreen = nil
        guard let focused, let path = root.path(of: focused) else { return }
        root.modify(at: Array(path.dropLast())) { c in
            if let mode {
                if mode == .accordion, c.mode != .accordion, autoOrientAccordions, !c.orientationChosen { c.orientation = .auto }
                c.mode = mode
            }
            if let orientation {
                c.orientation = orientation
                c.orientationChosen = true
            }
        }
        normalize()
    }

    /// Toggle fullscreen for the focused window. The tree is not changed.
    public mutating func toggleFullscreen() {
        fullscreen = fullscreen == nil ? focused : nil
    }

    /// Frames and stacking for every window. A fullscreen window covers the bounds minus outer gaps and comes first.
    public func layout() -> Layout {
        var result = tiledLayout()
        if let fullscreen {
            result.frames[fullscreen] = gaps.inset(bounds)
            result.order = [fullscreen] + result.order.filter { $0 != fullscreen }
        }
        return result
    }

    /// The layout ignoring fullscreen, used for geometry questions.
    func tiledLayout() -> Layout {
        var result = Layout()
        root.layout(in: gaps.inset(bounds), gaps: gaps, padding: accordionPadding, minimums: minimumSizes, into: &result)
        return result
    }

    /// Tidy the tree after an edit, and unwrap a root whose only child is a container.
    mutating func normalize() {
        root.normalize()
        if root.children.count == 1, case .container(let only) = root.children[0] { root = only }
    }
}
