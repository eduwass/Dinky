import CoreGraphics

extension Layout {
    /// Windows to raise, back to front, so overlapping windows (accordion, fullscreen) stack as `order` says.
    /// `current` is the on-screen order, front to back. Empty when it already agrees; plain tiles never overlap.
    public func raises(current: [WindowID]) -> [WindowID] {
        let overlapping = order.filter { id in
            frames.contains { other, rect in
                other != id && !rect.intersection(frames[id]!).isEmpty
            }
        }
        let wanted = Set(overlapping)
        return current.filter(wanted.contains) == overlapping ? [] : overlapping.reversed()
    }
}
