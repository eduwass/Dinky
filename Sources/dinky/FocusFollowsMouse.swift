import AppKit
import DinkyConfig
import DinkyLayout
import DinkyPrivate

// Focus follows mouse: a window the pointer comes to rest on takes focus. A listen-only tap sees mouse
// moves; at most every 50 ms the pointer is looked at, and only real movement counts, so windows moving
// under a still pointer (a retile, a Space switch) never take focus. The window must stay under the pointer
// for `delay-ms` before it is focused. Only windows dinky tracks count; panels, menus, the Dock and the
// desktop never do. After a Space change, a config load and an app activation hover did not cause (Cmd-Tab,
// a Dock click), hover parks until the pointer leaves the window it rests on: a hand on the mouse twitches, and
// that would focus the window being left and undo the activation. Leaving is judged against the windows as
// they are now, the one under the pointer against the one at the spot where it parked, so windows sliding or
// retiling under a still pointer never count. Main thread only.
final class HoverFocus {
    private var config = FocusFollowsMouse()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var evaluationPending = false
    private var lastEvaluatedAt: UInt64 = 0
    private var lastPoint = CGPoint(x: -1, y: -1)
    /// Where the last move event put the pointer. Read from the event: asking the system right away in
    /// the callback can still answer with the position before the move.
    private var latestPoint = CGPoint(x: -1, y: -1)
    /// Where the pointer rested at the last Space change, config load or activation hover did not cause. Hover
    /// is off until the pointer is over another window than the one at this spot.
    private var parkedAt: CGPoint?
    /// The app hover last activated itself, and when, so that activation does not park hover.
    private var ownActivation: (pid: pid_t, at: UInt64)?
    private var lastSpaces: [UInt64] = []
    private var dwell: DispatchWorkItem?
    private var observing = false

    private let throttle: UInt64 = 50_000_000
    /// How long after hover's own activation the activation notification may arrive.
    private let ownActivationWindow: UInt64 = 300_000_000
    private let minimumMove: CGFloat = 2

    /// Starts or stops the tap for this config. Called at startup and on every config load.
    func update(config: FocusFollowsMouse) {
        self.config = config
        if !observing {
            observing = true
            AppState.shared.displays.observe { [weak self] _ in self?.noteSpaces() }
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                              object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.activated(app.processIdentifier)
            }
        }
        lastSpaces = currentSpaces()
        park()
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

    fileprivate func handle(_ type: CGEventType, at location: CGPoint) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .mouseMoved, tap != nil else { return }
        latestPoint = location
        // Trailing throttle: the last move of a burst is always evaluated, at most every 50 ms.
        guard !evaluationPending else { return }
        evaluationPending = true
        let wait = max(0, Int64(lastEvaluatedAt + throttle) - Int64(uptime()))
        DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(Int(wait))) { [weak self] in self?.evaluate() }
    }

    private func evaluate() {
        evaluationPending = false
        lastEvaluatedAt = uptime()
        let point = latestPoint
        guard hypot(point.x - lastPoint.x, point.y - lastPoint.y) >= minimumMove else { return }
        lastPoint = point
        noteSpaces()
        if let parked = parkedAt {
            guard windowUnder(point) != windowUnder(parked) else { return cancel() }
            parkedAt = nil
        }
        guard let id = hoverable(at: point), id != AppState.shared.coordinator?.focusedWindow else { return cancel() }
        let spaces = currentSpaces()
        let work = DispatchWorkItem { [weak self] in self?.fire(id, spaces) }
        dwell?.cancel()
        dwell = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(config.delayMs), execute: work)
    }

    private func fire(_ id: WindowID, _ spaces: [UInt64]) {
        dwell = nil
        guard let point = CGEvent(source: nil)?.location, currentSpaces() == spaces,
              hoverable(at: point) == id, let coordinator = AppState.shared.coordinator,
              id != coordinator.focusedWindow else { return }
        ownActivation = (coordinator.model.windows[id]?.pid ?? 0, uptime())
        coordinator.focus(id)
    }

    /// An activation that is not hover's own cancels any hover and parks it.
    private func activated(_ pid: pid_t) {
        if let own = ownActivation, own.pid == pid, uptime() - own.at < ownActivationWindow {
            ownActivation = nil
            return
        }
        park()
    }

    /// The tracked window under the pointer, if hover may focus it now.
    private func hoverable(at point: CGPoint) -> WindowID? {
        let state = AppState.shared
        guard state.enabled, !MissionControl.shared.active,
              !CGEventSource.buttonState(.combinedSessionState, button: .left),
              let coordinator = state.coordinator, let id = windowUnder(point), coordinator.placements[id] != nil,
              !SpaceSwitcher.shared.switching else { return nil }
        // A dialog, sheet or alert has keyboard focus when the front app's focused window is one dinky has not
        // placed although it is on a current Space. Hover leaves it alone: focusing another window would bury
        // the dialog behind its app. An unplaced window on another Space (the front app's window after a
        // Cmd-Tab that was not followed, or on a Space dinky has not seen yet) is no dialog.
        let front = frontWindowID()
        if front != 0, coordinator.placements[front] == nil,
           coordinator.model.windows[front].map({ coordinator.isVisible($0.spaceID) }) ?? true { return nil }
        // An accordion child other than the front one only peeks out; with `accordion-edges = false` it stays put.
        if !config.accordionEdges, let container = coordinator.container(of: id), container.mode == .accordion,
           container.children[container.activeIndex] != .window(id) { return nil }
        return id
    }

    /// The frontmost window at the point among normal, floating and modal levels, if hover may look at it.
    /// Nil while a menu is open anywhere, a modal panel is up or dinky shows a window of its own, such as
    /// the update dialog: focusing another window would close or bury them. dinky's border windows are
    /// looked through; the Dock and Notification Center keep transparent windows over the whole screen at
    /// higher levels and are passed over.
    private func windowUnder(_ point: CGPoint) -> WindowID? {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        let modalLevel = Int(CGWindowLevelForKey(.modalPanelWindow))
        let layers = info.compactMap { $0[kCGWindowLayer as String] as? Int }
        if layers.contains(menuLevel) || layers.contains(modalLevel) { return nil }
        // dinky is an accessory app, so a dialog of its own never makes it the front app: the front app's
        // focused window stays a tile, and only the window list shows the dialog.
        let ownDialog = info.contains { w in
            w[kCGWindowOwnerPID as String] as? pid_t == getpid() && (0...modalLevel).contains(w[kCGWindowLayer as String] as? Int ?? -1)
                && AppState.shared.coordinator?.isBorderWindow(w[kCGWindowNumber as String] as? UInt32 ?? 0) != true
        }
        if ownDialog { return nil }
        let window = info.first { w in
            guard let layer = w[kCGWindowLayer as String] as? Int, (0...modalLevel).contains(layer),
                  let id = w[kCGWindowNumber as String] as? UInt32,
                  AppState.shared.coordinator?.isBorderWindow(id) != true,
                  (w[kCGWindowAlpha as String] as? Double ?? 0) > 0,
                  let bounds = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
            return rect.contains(point)
        }
        return window?[kCGWindowNumber as String] as? UInt32
    }

    /// Every display's current Space, read fresh.
    private func currentSpaces() -> [UInt64] {
        AppState.shared.displays.displays.map { dinky_current_space_id($0.uuid as CFString) }
    }

    /// A Space change since the last look cancels any hover and parks it.
    private func noteSpaces() {
        let spaces = currentSpaces()
        guard spaces != lastSpaces else { return }
        lastSpaces = spaces
        park()
    }

    private func park() {
        cancel()
        parkedAt = CGEvent(source: nil)?.location
    }

    private func cancel() {
        dwell?.cancel()
        dwell = nil
    }
}

private func hoverCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                           refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let refcon { Unmanaged<HoverFocus>.fromOpaque(refcon).takeUnretainedValue().handle(type, at: event.location) }
    return Unmanaged.passUnretained(event)
}
