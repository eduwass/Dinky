import AppKit
import DinkyPrivate

// A window as WindowServer sees it. Identity includes the owner pid and when dinky first saw
// the window, so a window ID reused by WindowServer is never mistaken for the old window.
struct Window {
    struct Identity: Hashable {
        let id: UInt32
        let pid: pid_t
        let firstSeen: Date  // model start for windows that existed before it
    }

    let identity: Identity
    let appName: String?
    let bundleID: String?
    var frame: CGRect = .zero
    var level = 0
    var spaceID: UInt64 = 0
    var isOrderedIn = false
    var isDocument = false
    var isMinimized = false
    var cornerRadius = 0

    var id: UInt32 { identity.id }
    var pid: pid_t { identity.pid }

    // Tileable: normal layer, on screen, a document window rather than a sheet, panel or popup.
    var isNormal: Bool { level == 0 && isOrderedIn && isDocument }
}

struct WindowEvent {
    enum Change { case added, removed, updated, none }

    let kind: DinkyEventKind
    let change: Change
    let window: Window?  // after the change; last known state for .removed
    let pid: pid_t       // window owner, or the new front app for .frontApp
    let spaceID: UInt64  // from the payload, when it carries one
    let time: Date
}

// The window table, seeded from WindowServer and kept current by its notifications.
// Main thread only: SkyLight's callbacks are hopped to the main queue before they touch it.
final class WindowModel {
    private(set) var windows: [UInt32: Window] = [:]
    var onChange: ((WindowEvent) -> Void)?

    private let ownPID = getpid()
    private var started = false

    /// Subscribes to the shared WindowServer stream and seeds the table. False if WindowServer refused.
    func start() -> Bool {
        guard !started else { return true }
        started = EventHub.shared.subscribe { [weak self] event in self?.handle(event) }
        guard started else { return false }
        seed()
        return true
    }

    // Sanity pass for callers that suspect drift: drops windows that no longer exist,
    // adds any the events missed, refreshes the rest. Publishes what changed.
    func reconcile() {
        for window in windows.values where !dinky_window_info(window.id).exists {
            remove(window.id, kind: .windowDestroy)
        }
        for id in dinky_all_window_ids().map(\.uint32Value) {
            if windows[id] == nil {
                add(id, spaceID: 0, kind: .windowCreate)
            } else {
                refresh(id, kind: .windowUpdate)
            }
        }
    }

    private func seed() {
        let now = Date()
        for id in dinky_all_window_ids().map(\.uint32Value) {
            if let window = makeWindow(id, spaceID: 0, firstSeen: now) { windows[id] = window }
        }
        watch()
    }

    private func handle(_ event: DinkyEvent) {
        let id = event.windowID
        switch event.kind {
        case .windowCreate:
            // A reused ID from another process is a new window.
            if let old = windows[id], old.pid != event.pid { remove(id, kind: .windowDestroy) }
            if windows[id] == nil { add(id, spaceID: event.spaceID, kind: event.kind) } else { refresh(id, kind: event.kind) }
        case .windowDestroy:
            // JankyBorders treats 1326 as "left this Space"; the window may still exist elsewhere.
            if dinky_window_info(id).exists { refresh(id, kind: event.kind) } else { remove(id, kind: event.kind) }
        case .windowClose:
            remove(id, kind: event.kind)
        case .spaceChange, .spaceCreated, .spaceDestroyed, .frontApp:
            publish(event.kind, .none, nil, pid: event.pid, spaceID: event.spaceID)
        default:
            if windows[id] != nil {
                refresh(id, kind: event.kind)
            } else {
                publish(event.kind, .none, nil, pid: event.pid)
            }
        }
    }

    private func add(_ id: UInt32, spaceID: UInt64, kind: DinkyEventKind) {
        guard let window = makeWindow(id, spaceID: spaceID, firstSeen: Date()) else {
            publish(kind, .none, nil, pid: 0, spaceID: spaceID)
            return
        }
        windows[id] = window
        watch()
        publish(kind, .added, window, pid: window.pid, spaceID: spaceID)
    }

    private func remove(_ id: UInt32, kind: DinkyEventKind) {
        guard let window = windows.removeValue(forKey: id) else {
            publish(kind, .none, nil, pid: 0)
            return
        }
        watch()
        publish(kind, .removed, window, pid: window.pid)
    }

    private func refresh(_ id: UInt32, kind: DinkyEventKind) {
        guard var window = windows[id] else { return }
        let info = dinky_window_info(id)
        guard info.exists else { return remove(id, kind: kind) }
        apply(info, to: &window)
        window.spaceID = dinky_window_space_id(id)
        windows[id] = window
        publish(kind, .updated, window, pid: window.pid)
    }

    // nil for dinky's own windows, windows that are already gone and child windows.
    private func makeWindow(_ id: UInt32, spaceID: UInt64, firstSeen: Date) -> Window? {
        let info = dinky_window_info(id)
        guard info.exists, info.pid != 0, info.pid != ownPID, info.parentID == 0 else { return nil }
        let app = NSRunningApplication(processIdentifier: info.pid)
        var window = Window(
            identity: .init(id: id, pid: info.pid, firstSeen: firstSeen),
            appName: app?.localizedName,
            bundleID: app?.bundleIdentifier
        )
        apply(info, to: &window)
        window.spaceID = spaceID != 0 ? spaceID : dinky_window_space_id(id)
        return window
    }

    private func apply(_ info: DinkyWindowInfo, to window: inout Window) {
        window.frame = info.frame
        window.level = Int(info.level)
        window.isOrderedIn = info.isOrderedIn
        window.isDocument = info.isDocument
        window.isMinimized = info.isMinimized
        window.cornerRadius = Int(info.cornerRadius)
    }

    private func watch() {
        let ids = Array(windows.keys)
        dinky_events_watch_windows(ids, Int32(ids.count))
    }

    private func publish(_ kind: DinkyEventKind, _ change: WindowEvent.Change, _ window: Window?, pid: pid_t, spaceID: UInt64 = 0) {
        onChange?(WindowEvent(kind: kind, change: change, window: window, pid: pid, spaceID: spaceID, time: Date()))
    }
}
