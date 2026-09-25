import AppKit
import DinkyLayout

// Applies a layout through Accessibility. Scheduling (a queue per app, newest frame wins, one retry)
// lives in FrameScheduler; this file is only the AX side: element lookup, writes, readback, raises.
final class FrameApplier {
    /// How long one AX call to an app may block before giving up, so a hung app only stalls its own queue.
    static let timeout: Float = 1

    private var scheduler: FrameScheduler!
    private let lock = NSLock()
    private var elements: [WindowID: AXUIElement] = [:]
    private let raiseQueue = DispatchQueue(label: "dinky.frames.raise")

    init() {
        scheduler = FrameScheduler(
            prepare: { pid in
                // Enhanced UI (set by VoiceOver and some utilities) makes apps animate and fight frame writes.
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, Self.timeout)
                AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
            },
            read: { [unowned self] job in element(pid: job.pid, id: job.id).flatMap(frame) },
            write: { [unowned self] job in element(pid: job.pid, id: job.id).map { write(job.frame, to: $0) } }
        )
    }

    /// Sizes windows refused to shrink below, from readback.
    var minimumSizes: [WindowID: CGSize] { scheduler.minimumSizes }

    /// Drops every frame not written yet.
    func cancel() { scheduler.cancel() }

    /// Write every frame in `layout`, then raise overlapping windows into the layout's order if they are not.
    /// `completion` runs on a background queue with the readback of every app touched.
    func apply(_ layout: Layout, pids: [WindowID: pid_t], completion: @escaping ([FrameResult]) -> Void = { _ in }) {
        let jobs = layout.order.compactMap { id in
            pids[id].map { FrameJob(pid: $0, id: id, frame: layout.frames[id]!) }
        }
        scheduler.submit(jobs) { [unowned self] results in
            raiseQueue.async {
                self.raise(layout.raises(current: onScreenOrder()), pids: pids)
                completion(results)
            }
        }
    }

    /// Raise back to front, so the last raised ends up frontmost. AXRaise does not activate the app.
    private func raise(_ ids: [WindowID], pids: [WindowID: pid_t]) {
        for id in ids {
            guard let pid = pids[id], let element = element(pid: pid, id: id) else { continue }
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        }
    }

    private func element(pid: pid_t, id: WindowID) -> AXUIElement? {
        if let cached = lock.withLock({ elements[id] }) { return cached }
        guard let element = axWindow(pid: pid, wid: id, timeout: Self.timeout) else { return nil }
        lock.withLock { elements[id] = element }
        return element
    }

    // Size, position, size: the first size lets a window near the screen edge move, the second
    // fixes the size if the move clamped it.
    private func write(_ frame: CGRect, to element: AXUIElement) {
        var size = frame.size, origin = frame.origin
        let sizeValue = AXValueCreate(.cgSize, &size)!, originValue = AXValueCreate(.cgPoint, &origin)!
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, originValue)
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
    }

    private func frame(_ element: AXUIElement) -> CGRect? {
        var origin = CGPoint.zero, size = CGSize.zero
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
              AXValueGetValue(value as! AXValue, .cgPoint, &origin),
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success,
              AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }
}

/// On-screen windows, front to back.
func onScreenOrder() -> [WindowID] {
    let info = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    return info.compactMap { $0[kCGWindowNumber as String] as? WindowID }
}
