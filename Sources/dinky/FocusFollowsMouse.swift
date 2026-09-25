import AppKit
import DinkyConfig
import DinkyLayout
import DinkyPrivate

// Focus follows mouse: a window the pointer comes to rest on takes focus. A listen-only tap sees mouse
// moves; at most every 50 ms the pointer is looked at, and only real movement counts, so windows moving
// under a still pointer (a retile, a Space switch) never take focus. The window must stay under the pointer
// for `delay-ms` before it is focused. Only windows dinky tracks count; panels, menus, the Dock and the
// desktop never do. Main thread only.
final class HoverFocus {
    private var config = FocusFollowsMouse()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var evaluationPending = false
    private var lastEvaluatedAt: UInt64 = 0
    private var lastPoint = CGPoint(x: -1, y: -1)
    /// Hover is ignored until then: just after a Space change or a config reload.
    private var quietUntil: UInt64 = 0
    private var lastSpaces: [UInt64] = []
    private var dwell: DispatchWorkItem?
    private var observing = false

    private let throttle: UInt64 = 50_000_000
    private let quiet: UInt64 = 300_000_000
    private let minimumMove: CGFloat = 2

    /// Starts or stops the tap for this config. Called at startup and on every config load.
    func update(config: FocusFollowsMouse) {
        self.config = config
        if !observing {
            observing = true
            AppState.shared.displays.observe { [weak self] _ in self?.noteSpaces() }
        }
        lastSpaces = currentSpaces()
        cancel(quietFor: quiet)
        if config.enabled { start() } else { stop() }
    }

    private func start() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.mouseMoved.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: hoverCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            fputs("focus-follows-mouse: could not create event tap (Accessibility?)\n", stderr)
            return
        }
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
    }

    private func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        CFMachPortInvalidate(tap)
        (self.tap, source) = (nil, nil)
    }

    fileprivate func handle(_ type: CGEventType) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        // Trailing throttle: the last move of a burst is always evaluated, at most every 50 ms.
        guard type == .mouseMoved, tap != nil, !evaluationPending else { return }
        evaluationPending = true
        let wait = max(0, Int64(lastEvaluatedAt + throttle) - Int64(now()))
        DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(Int(wait))) { [weak self] in self?.evaluate() }
    }

    private func evaluate() {
        evaluationPending = false
        lastEvaluatedAt = now()
        guard let point = CGEvent(source: nil)?.location, hypot(point.x - lastPoint.x, point.y - lastPoint.y) >= minimumMove else { return }
        lastPoint = point
        noteSpaces()
        guard let id = hoverable(at: point), id != AppState.shared.coordinator?.focusedWindow else { return cancel() }
        let space = currentSpaces()
        let work = DispatchWorkItem { [weak self] in self?.fire(id, space) }
        dwell?.cancel()
        dwell = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(config.delayMs), execute: work)
    }

    private func fire(_ id: WindowID, _ spaces: [UInt64]) {
        dwell = nil
        guard let point = CGEvent(source: nil)?.location, currentSpaces() == spaces,
              hoverable(at: point) == id, let coordinator = AppState.shared.coordinator,
              id != coordinator.focusedWindow else { return }
        coordinator.focus(id)
    }

    /// The tracked window under the pointer, if hover may focus it now.
    private func hoverable(at point: CGPoint) -> WindowID? {
        let state = AppState.shared
        guard state.enabled, now() >= quietUntil, !CGEventSource.buttonState(.combinedSessionState, button: .left),
              let coordinator = state.coordinator, let id = windowUnder(point), coordinator.placements[id] != nil,
              !state.displays.displays.contains(where: { SpaceSwitcher.shared.target(on: $0.uuid) != nil }) else { return nil }
        // An accordion child other than the front one only peeks out; with `accordion = false` it stays put.
        if !config.accordion, let container = coordinator.container(of: id), container.mode == .accordion,
           container.children[min(container.active, container.children.count - 1)] != .window(id) { return nil }
        return id
    }

    /// The frontmost normal (layer 0) window at the point. Nil while a menu is open anywhere: focusing another
    /// app would close it. Higher layers are passed over: the Dock and Notification Center keep transparent
    /// windows over the whole screen.
    private func windowUnder(_ point: CGPoint) -> WindowID? {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        if info.contains(where: { $0[kCGWindowLayer as String] as? Int == menuLevel }) { return nil }
        let window = info.first { w in
            guard w[kCGWindowLayer as String] as? Int == 0, w[kCGWindowOwnerPID as String] as? pid_t != getpid(),
                  (w[kCGWindowAlpha as String] as? Double ?? 0) > 0,
                  let bounds = w[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
            return CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0).contains(point)
        }
        return window?[kCGWindowNumber as String] as? UInt32
    }

    /// Every display's current Space, read fresh.
    private func currentSpaces() -> [UInt64] {
        AppState.shared.displays.displays.map { dinky_current_space_id($0.uuid as CFString) }
    }

    /// A Space change since the last look cancels any hover and starts the quiet period.
    private func noteSpaces() {
        let spaces = currentSpaces()
        guard spaces != lastSpaces else { return }
        lastSpaces = spaces
        cancel(quietFor: quiet)
    }

    private func cancel(quietFor duration: UInt64 = 0) {
        dwell?.cancel()
        dwell = nil
        if duration > 0 { quietUntil = now() + duration }
    }

    private func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }
}

private func hoverCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                           refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let refcon { Unmanaged<HoverFocus>.fromOpaque(refcon).takeUnretainedValue().handle(type) }
    return Unmanaged.passUnretained(event)
}
