import AppKit
import DinkyLayout

// Dragging a tiled window with the mouse. On release, a drag that moved one edge of the window on an axis is a
// resize: the tree takes the new size and the other tiles make room. Any other drag is a move: dropping the window
// over another tile swaps the two, anywhere else puts it back. Only frames that change while the mouse button is
// down count as a drag, which keeps dinky's own frame writes and apps moving themselves out of it.
extension Coordinator {
    func noteFrameChange(of id: WindowID) {
        // Only tiled windows have a Space.
        guard dragging == nil, placements[id]?.space != nil, mouseButtonDown else { return }
        dragging = id
        watchDragEnd()
    }

    private func watchDragEnd() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, let id = self.dragging else { return }
            if self.mouseButtonDown { self.watchDragEnd() } else { self.dragging = nil; self.dropped(id) }
        }
    }

    private func dropped(_ id: WindowID) {
        guard let key = placements[id]?.space, let frames = workspaces[key]?.layout().frames, let window = model.windows[id],
              let expected = frames[id], !window.frame.isClose(to: expected, within: 2) else { return }
        if let edges = movedEdges(from: expected, to: window.frame) {
            edit(key) { $0.resize(id, to: window.frame.size, moving: edges) }
        } else {
            let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
            let target = frames.first { $0.key != id && $0.value.contains(center) }?.key
            if let target { edit(key) { $0.swap(id, target) } }
        }
        dirty.insert(key)
        flush()
    }

    /// The edges a resize moved, going from the tile to the dropped frame: on each axis, one edge moved more than
    /// 2 pt and the other stayed. Nil for a move, where some axis had both edges move, or nothing did.
    private func movedEdges(from tile: CGRect, to frame: CGRect) -> Set<Direction>? {
        let axes = [((Direction.left, tile.minX, frame.minX), (Direction.right, tile.maxX, frame.maxX)),
                    ((Direction.up, tile.minY, frame.minY), (Direction.down, tile.maxY, frame.maxY))]
        var edges: Set<Direction> = []
        for (lead, trail) in axes {
            let moved = [lead, trail].filter { abs($0.2 - $0.1) > 2 }.map(\.0)
            if moved.count == 2 { return nil }
            edges.formUnion(moved)
        }
        return edges.isEmpty ? nil : edges
    }

    private var mouseButtonDown: Bool { CGEventSource.buttonState(.combinedSessionState, button: .left) }
}
