import AppKit
import DinkyLayout

// Dragging a tiled window with the mouse: on release, dropping it over another tile swaps the two,
// anywhere else puts it back. Only frames that change while the mouse button is down count as a drag,
// which keeps dinky's own frame writes and apps moving themselves out of it.
extension Coordinator {
    func noteFrameChange(of id: WindowID) {
        guard dragging == nil, let placement = placements[id], !placement.floating, placement.space != nil,
              mouseButtonDown else { return }
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
        guard let key = placements[id]?.space, let workspace = workspaces[key], let window = model.windows[id],
              let expected = workspace.layout().frames[id], !window.frame.isClose(to: expected, within: 2) else { return }
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        let target = workspace.layout().frames.first { $0.key != id && $0.value.contains(center) }?.key
        if let target { edit(key) { $0.swap(id, target) } }
        dirty.insert(key)
        flush()
    }

    private var mouseButtonDown: Bool { CGEventSource.buttonState(.combinedSessionState, button: .left) }
}
