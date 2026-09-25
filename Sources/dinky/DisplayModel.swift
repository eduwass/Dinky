import AppKit
import DinkyPrivate

// Fans the one process-wide WindowServer callback out to every model that wants events.
// dinky_events_start keeps a single callback, so exactly one owner may call it: this hub.
// Subscribers run on the main queue.
final class EventHub {
    static let shared = EventHub()
    private var subscribers: [(DinkyEvent) -> Void] = []
    private var started = false

    /// Starts the stream on first use. False if WindowServer refused the registration.
    @discardableResult
    func subscribe(_ handler: @escaping (DinkyEvent) -> Void) -> Bool {
        subscribers.append(handler)
        guard !started else { return true }
        started = dinky_events_start({ event, _ in
            DispatchQueue.main.async { EventHub.shared.subscribers.forEach { $0(event) } }
        }, nil)
        return started
    }
}

/// One display as the model last read it.
struct Display: Equatable {
    let uuid: String
    let id: CGDirectDisplayID
    /// Global CG coordinates, top-left origin.
    let frame: CGRect
    let isMain: Bool
    /// Every Space in Mission Control order, full-screen ones included. Swipes step over all of them.
    let spaces: [UInt64]
    /// User Spaces only: workspace N is `workspaces[N - 1]`. Full-screen Spaces are not numbered.
    let workspaces: [UInt64]
    let currentSpaceID: UInt64

    /// 0-based workspace index of the current Space, nil on a full-screen Space.
    var currentWorkspace: Int? { workspaces.firstIndex(of: currentSpaceID) }
}

// Displays, their Spaces, the current and previous Space per display, and which display has focus.
// Refreshed from WindowServer Space events, screen reconfiguration and `reconcile()`. Main thread only.
final class DisplayModel {
    private(set) var displays: [Display] = []
    /// The Space each display was on before its current one, by display UUID, for back-and-forth.
    private var previousSpaceIDs: [String: UInt64] = [:]
    private var observers: [(DisplayModel) -> Void] = []
    /// The UUID of a display `focus-monitor` focused without a window to focus there. It stands in for the
    /// focused window's display until focus next changes.
    var focusOverride: String?

    /// Reads the displays and follows their changes from then on. Call once.
    func start() {
        reconcile()
        EventHub.shared.subscribe { [weak self] event in
            switch event.kind {
            case .spaceChange, .spaceCreated, .spaceDestroyed: self?.reconcile()
            default: break
            }
        }
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.reconcile()
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            self?.reconcile()
        }
    }

    /// Re-reads every display from WindowServer. Records previous Spaces and publishes if anything changed.
    func reconcile() {
        let fresh = readDisplays()
        guard fresh != displays else { return }
        for display in fresh {
            if let old = displays.first(where: { $0.uuid == display.uuid }), old.currentSpaceID != display.currentSpaceID {
                previousSpaceIDs[display.uuid] = old.currentSpaceID
            }
        }
        // A disconnected display takes its history with it.
        previousSpaceIDs = previousSpaceIDs.filter { uuid, _ in fresh.contains { $0.uuid == uuid } }
        displays = fresh
        observers.forEach { $0(self) }
    }

    /// Calls `handler` after every change, in the order observers were added.
    func observe(_ handler: @escaping (DisplayModel) -> Void) {
        observers.append(handler)
    }

    /// The display chosen by `focus-monitor`, else that of the focused window, else the one under the cursor,
    /// else the main display.
    func focusedDisplay() -> Display? {
        if let chosen = displays.first(where: { $0.uuid == focusOverride }) { return chosen }
        let wid = frontWindowID()
        if wid != 0, let display = display(ofWindow: wid) { return display }
        if let cursor = CGEvent(source: nil)?.location, let display = displays.first(where: { $0.frame.contains(cursor) }) {
            return display
        }
        return displays.first(where: \.isMain) ?? displays.first
    }

    /// The display showing the window's Space, or failing that the one containing its frame's centre.
    func display(ofWindow wid: UInt32) -> Display? {
        if let display = display(containingSpace: dinky_window_space_id(wid)) { return display }
        let info = dinky_window_info(wid)
        guard info.exists else { return nil }
        return displays.first { $0.frame.contains(CGPoint(x: info.frame.midX, y: info.frame.midY)) }
    }

    func display(containingSpace spaceID: UInt64) -> Display? {
        spaceID == 0 ? nil : displays.first { $0.spaces.contains(spaceID) }
    }

    /// 0-based workspace index of the display's previous Space, if it is still a numbered workspace.
    func previousWorkspace(on display: Display) -> Int? {
        previousSpaceIDs[display.uuid].flatMap { display.workspaces.firstIndex(of: $0) }
    }

    private func readDisplays() -> [Display] {
        dinky_displays().compactMap { d in
            // Skip a display that went away between the Space query and now; its bounds would be stale.
            guard d.displayID != 0, CGDisplayIsOnline(d.displayID) != 0 else { return nil }
            return Display(uuid: d.uuid, id: d.displayID, frame: CGDisplayBounds(d.displayID),
                           isMain: CGDisplayIsMain(d.displayID) != 0,
                           spaces: d.spaces.map(\.spaceID),
                           workspaces: d.spaces.filter(\.isUser).map(\.spaceID),
                           currentSpaceID: d.currentSpaceID)
        }
    }
}
