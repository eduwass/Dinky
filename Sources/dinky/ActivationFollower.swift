import AppKit
import DinkyPrivate

// Follows app activation (Cmd-Tab, Dock click) to the display and Space of the app's window when the
// "switch to a Space with open windows" setting is off. Only activations the user asked for are followed.
// macOS also activates apps on its own, and chasing those throws the user off the Space they are on:
// - Arriving on a Space activates whatever is there (Finder on an empty one). The first activation within
//   `arrivalWindow` of a Space change is that one.
// - When the active app quits, hides or loses its last window on the current Space, macOS activates another
//   app. An activation within `goneWindow` of the previous app going away is that one.
// - Opening a document activates the app before its new window exists. An app with no window on the
//   current Space gets `windowGrace` for one to appear there before it is followed.

var followEnabled = true

private let ms: UInt64 = 1_000_000
private let arrivalWindow = 300 * ms
private let goneWindow = 300 * ms
private let windowGrace = 250 * ms

// The Space-change notification is not reliable for swipes posted by other processes, so the last Space
// seen on each display is remembered too, and checked on every activation and by a timer.
private var lastSeenSpaceIDs: [String: UInt64] = [:]
private var lastSpaceChangeAt: UInt64 = 0
/// No activation has arrived since the last Space change.
private var arrivalPending = false
/// The app that last quit, hid or lost a window, and when.
private var lastGone: (pid: pid_t, at: UInt64) = (0, 0)
private var activePID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
/// Counts activations, so a follow waiting for a window knows when a newer activation replaced it.
private var activations = 0
/// The last few follows, to notice a loop: dinky and macOS chasing each other's activations between two
/// Spaces. `loopFollows` follows within `loopWindow` pause following for `loopPause`, logged with the trail.
private var recentFollows: [(at: UInt64, text: String)] = []
private var pausedUntil: UInt64 = 0
private let loopFollows = 4
private let loopWindow = 3_000 * ms
private let loopPause = 5_000 * ms

// Records the current Space of every display; a difference from the last one recorded is a Space change.
private func noteCurrentSpace() {
    let model = AppState.shared.displays
    model.reconcile()
    let seen = Dictionary(model.displays.map { ($0.uuid, $0.currentSpaceID) }, uniquingKeysWith: { a, _ in a })
    guard seen != lastSeenSpaceIDs else { return }
    lastSeenSpaceIDs = seen
    spaceChanged()
}

// Tells the activation follower that this Space change, or this activation on the current Space, is
// dinky's own, so the activation it causes is not followed.
func noteOwnSwitch(to target: UInt64, on uuid: String) {
    lastSeenSpaceIDs[uuid] = target
    spaceChanged()
}

private func spaceChanged() {
    lastSpaceChangeAt = uptime()
    arrivalPending = true
}

func installActivationFollower() {
    noteCurrentSpace()
    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in noteCurrentSpace() }
    EventHub.shared.subscribe { event in
        switch event.kind {
        case .spaceChange:
            noteCurrentSpace()
        case .windowClose, .windowDestroy:
            // Runs before the coordinator's model forgets the window, which knows its owner once it is gone.
            let pid = event.pid != 0 ? event.pid : AppState.shared.coordinator?.model.windows[event.windowID]?.pid
            if let pid { lastGone = (pid, uptime()) }
        default:
            break
        }
    }
    let center = NSWorkspace.shared.notificationCenter
    for name in [NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didHideApplicationNotification] {
        center.addObserver(forName: name, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            lastGone = (app.processIdentifier, uptime())
        }
    }
    center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let previous = activePID
        activePID = app.processIdentifier
        activations += 1
        let name = app.localizedName ?? "?"
        guard followEnabled else { return }
        guard uptime() >= pausedUntil else { return log("activate \(name): not followed, following is paused") }
        guard !isArrivalActivation() else { return log("activate \(name): not followed, macOS activated it on arrival") }
        activated(app.processIdentifier, name: name, previous: previous)
    }
}

// Consumes the arrival: only the first activation after a Space change can be the one it causes.
private func isArrivalActivation() -> Bool {
    noteCurrentSpace()
    defer { arrivalPending = false }
    return arrivalPending && uptime() - lastSpaceChangeAt < arrivalWindow
}

// Stays if the app has a window on the focused display's current Space: then Cmd-Tab brings that window
// forward. Otherwise waits for one to appear there, then follows the app unless the activation was macOS
// replacing an app that went away, or something else happened meanwhile.
private func activated(_ pid: pid_t, name: String, previous: pid_t) {
    guard let here = AppState.shared.displays.focusedDisplay()?.currentSpaceID else {
        return log("activate \(name): not followed, no focused display")
    }
    guard !windowSpaces(of: pid).contains(here) else { return log("activate \(name): stayed, it has a window here") }
    let activatedAt = uptime()
    let activation = activations
    DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(Int(windowGrace))) {
        if activation != activations {
            log("activate \(name): not followed, another app was activated")
        } else if lastSpaceChangeAt >= activatedAt {
            log("activate \(name): not followed, the Space changed meanwhile")
        } else if windowSpaces(of: pid).contains(here) {
            log("activate \(name): stayed, its new window opened here")
        } else if lastGone.pid == previous, lastGone.at + goneWindow > activatedAt, !hasWindowOnScreen(previous) {
            log("activate \(name): not followed, macOS replaced the app that went away")
        } else {
            follow(pid, name: name)
        }
    }
}

private func log(_ message: String) {
    print("\(stamp()) \(message)")
    fflush(stdout)
}

// Remembers a follow, and pauses following when they come too fast to be the user's doing.
private func noteFollow(_ text: String) {
    let now = uptime()
    recentFollows = recentFollows.filter { now - $0.at < loopWindow } + [(now, text)]
    guard recentFollows.count >= loopFollows else { return }
    pausedUntil = now + loopPause
    let trail = recentFollows.map { String(format: "%.0f ms ago: %@", Double(now - $0.at) / 1_000_000, $0.text) }
    fputs("\(stamp()) activate: \(recentFollows.count) follows in \(loopWindow / (1_000 * ms)) s look like a loop; "
        + "not following for \(loopPause / (1_000 * ms)) s\n  " + trail.joined(separator: "\n  ") + "\n", stderr)
    recentFollows = []
}

// The Spaces of the app's normal windows, front to back: the first one is its frontmost window's.
private func windowSpaces(of pid: pid_t) -> [UInt64] {
    normalWindows(of: pid, [.optionAll]).map { dinky_window_space_id($0) }
}

// Whether the app shows a normal window on a current Space; a hidden app does not.
private func hasWindowOnScreen(_ pid: pid_t) -> Bool {
    !normalWindows(of: pid, [.optionOnScreenOnly]).isEmpty
}

// Only the windows the window model tracks as normal count, so an app's hidden helper windows, which can sit
// on any Space, don't. The window server's list supplies the front-to-back order.
private func normalWindows(of pid: pid_t, _ options: CGWindowListOption) -> [UInt32] {
    let known = AppState.shared.coordinator?.model.windows ?? [:]
    let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
    return info.compactMap { w in
        guard w[kCGWindowOwnerPID as String] as? pid_t == pid, w[kCGWindowLayer as String] as? Int == 0,
              let id = w[kCGWindowNumber as String] as? UInt32, known[id]?.isNormal == true else { return nil }
        return id
    }
}

// Switches to the Space of the app's frontmost window.
private func follow(_ pid: pid_t, name: String) {
    let model = AppState.shared.displays
    guard uptime() >= pausedUntil else { return log("activate \(name): not followed, following is paused") }
    let windowSpaceIDs = windowSpaces(of: pid)
    guard let (space, display) = windowSpaceIDs.lazy.compactMap({ sid in model.display(containingSpace: sid).map { (sid, $0) } }).first else {
        return log("activate \(name): not followed, no display has its windows' Spaces \(windowSpaceIDs)")
    }
    guard space != display.currentSpaceID, switchSpace(toSpaceID: space, on: display) else {
        return log("activate \(name): not followed, already on Space \(space)")
    }
    let spaces = display.spaces
    let text = String(format: "activate %@: followed %d -> %d on %@", name,
                      (spaces.firstIndex(of: display.currentSpaceID) ?? -1) + 1, (spaces.firstIndex(of: space) ?? -1) + 1,
                      display.name.isEmpty ? "display \(display.id)" : display.name)
    log(text)
    noteFollow(text)
}
