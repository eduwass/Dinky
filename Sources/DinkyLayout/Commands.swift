import CoreGraphics

/// Directional commands and resize. Each returns false when there was nothing to do.
extension Workspace {
    /// Smallest share a window can be resized down to.
    public static let minimumRatio = 0.1

    /// The window in `direction` from `id`. Uses a virtual layout where accordions are split like tiles,
    /// so stacked accordion children still have a left and right. Ties go to the most recently focused window.
    public func neighbor(of id: WindowID, _ direction: Direction) -> WindowID? {
        var layout = Layout()
        root.layout(in: bounds, gap: 0, padding: 0, virtual: true, into: &layout)
        guard let from = layout.frames[id] else { return nil }
        let candidates = layout.order.compactMap { other -> (id: WindowID, distance: CGFloat)? in
            guard other != id, let to = layout.frames[other] else { return nil }
            let distance = switch direction {
            case .left: from.midX - to.midX
            case .right: to.midX - from.midX
            case .up: from.midY - to.midY
            case .down: to.midY - from.midY
            }
            let overlaps = direction.orientation == .horizontal
                ? min(from.maxY, to.maxY) > max(from.minY, to.minY)
                : min(from.maxX, to.maxX) > max(from.minX, to.minX)
            return distance > 0 && overlaps ? (other, distance) : nil
        }
        return candidates.min { $0.distance < $1.distance }?.id
    }

    /// Swap the focused window with its neighbour in `direction`. Focus stays with the moved window.
    @discardableResult
    public mutating func swap(_ direction: Direction) -> Bool {
        guard let focused, let other = neighbor(of: focused, direction),
              let a = root.path(of: focused), let b = root.path(of: other) else { return false }
        root.modify(at: Array(a.dropLast())) { $0.replace(at: a.last!, with: .window(other)) }
        root.modify(at: Array(b.dropLast())) { $0.replace(at: b.last!, with: .window(focused)) }
        focus(focused)
        return true
    }

    /// Move the focused window one step in `direction`, AeroSpace style: swap with a sibling window, enter a
    /// sibling container, or leave the container at its edge. At the workspace edge, wraps the root in a new
    /// container along that axis; if the root already runs that way, does nothing.
    @discardableResult
    public mutating func move(_ direction: Direction) -> Bool {
        guard let focused, let path = root.path(of: focused) else { return false }
        let axis = direction.orientation, step = direction.isForward ? 1 : 0
        let parentPath = Array(path.dropLast()), index = path.last!
        let parent = root.container(at: parentPath)
        let sibling = index + (direction.isForward ? 1 : -1)
        if parent.orientation == axis, parent.children.indices.contains(sibling) {
            guard case .container = parent.children[sibling] else { return swap(direction) }
            var destination = parentPath + [sibling]
            while case .container(let c) = root.node(at: destination), c.orientation != axis {
                destination.append(c.activeIndex)
            }
            detach(focused, adjusting: &destination)
            if case .container(let c) = root.node(at: destination) {
                root.modify(at: destination) { $0.insert(.window(focused), at: step == 1 ? 0 : c.children.count) }
            } else {
                root.modify(at: Array(destination.dropLast())) { $0.insert(.window(focused), at: destination.last! + 1) }
            }
        } else if let depth = path.indices.dropLast().last(where: { root.container(at: Array(path.prefix($0))).orientation == axis }) {
            var outer = Array(path.prefix(depth + 1))
            detach(focused, adjusting: &outer)
            root.modify(at: Array(outer.dropLast())) { $0.insert(.window(focused), at: outer.last! + step) }
        } else if root.orientation != axis {
            root.modify(at: parentPath) { $0.remove(at: index) }
            root = Container(axis, .tiles, [.container(root)])
            root.insert(.window(focused), at: step == 1 ? 1 : 0)
        } else {
            return false
        }
        normalize()
        focus(focused)
        return true
    }

    /// Put the focused window into the neighbouring subtree in `direction`: into it if it is a container
    /// across the axis, else into a new container wrapping the neighbour. Adapted from AeroSpace's join-with.
    @discardableResult
    public mutating func join(_ direction: Direction) -> Bool {
        guard let focused, let path = root.path(of: focused) else { return false }
        let offset = direction.isForward ? 1 : -1
        guard let depth = path.indices.last(where: { depth in
            let c = root.container(at: Array(path.prefix(depth)))
            return c.orientation == direction.orientation && c.children.indices.contains(path[depth] + offset)
        }) else { return false }
        var target = Array(path.prefix(depth)) + [path[depth] + offset]
        detach(focused, adjusting: &target)
        let across = direction.orientation.opposite
        switch root.node(at: target) {
        case .container(let c) where c.orientation == across:
            root.modify(at: target) { $0.insert(.window(focused), at: offset == 1 ? 0 : c.children.count) }
        case let node:
            let pair: [Node] = offset == 1 ? [.window(focused), node] : [node, .window(focused)]
            root.modify(at: Array(target.dropLast())) { $0.replace(at: target.last!, with: .container(Container(across, .tiles, pair))) }
        }
        normalize()
        focus(focused)
        return true
    }

    /// Grow (positive) or shrink the focused window by `delta` points along its nearest tiles container's axis.
    /// Siblings give or take space proportionally; no share drops below `minimumRatio`.
    @discardableResult
    public mutating func resize(by delta: CGFloat) -> Bool {
        guard let focused, var path = root.path(of: focused) else { return false }
        while let index = path.popLast() {
            let parent = root.container(at: path)
            guard parent.mode == .tiles, parent.children.count > 1 else { continue }
            let rect = root.rect(at: path, in: gaps.inset(bounds))
            let extent = parent.orientation == .horizontal ? rect.width : rect.height
            let old = parent.ratios[index]
            let smallestOther = parent.ratios.enumerated().filter { $0.offset != index }.map(\.element).min()!
            let upper = 1 - Self.minimumRatio * (1 - old) / smallestOther
            let new = min(max(old + Double(delta / extent), Self.minimumRatio), upper)
            guard abs(new - old) > 1e-9 else { return false }
            let scale = (1 - new) / (1 - old)
            root.modify(at: path) { c in c.setRatios(c.ratios.enumerated().map { $0.offset == index ? new : $0.element * scale }) }
            return true
        }
        return false
    }

    /// Remove a window's leaf without normalizing, shifting `path` if it pointed past the removed sibling.
    private mutating func detach(_ id: WindowID, adjusting other: inout [Int]) {
        let path = root.path(of: id)!
        let level = path.count - 1
        root.modify(at: Array(path.prefix(level))) { $0.remove(at: path[level]) }
        if other.count > level, Array(other.prefix(level)) == Array(path.prefix(level)), other[level] > path[level] {
            other[level] -= 1
        }
    }
}
