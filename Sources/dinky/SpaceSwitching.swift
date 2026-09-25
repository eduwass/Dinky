import AppKit
import DinkyPrivate

// Switching a display's Space with mimi's swipe, and following app activation (Cmd-Tab, Dock click) to
// the display and Space of the app's window when the "switch to a Space with open windows" setting is
// off. Shared by the app and the dispatcher.

var followEnabled = true
// Arriving on a Space activates whatever is there (Finder on an empty one). Those activations must not
// be followed, or an empty Space bounces straight back to Finder's window. The Space-change notification
// is not reliable for swipes posted by other processes, so remember the last Space we saw on each display
// instead: an activation that arrives after an unseen Space change is a consequence of that change, not a
// Cmd-Tab. Activation notifications can arrive a few hundred ms after the arrival, so a change noticed by
// the timer also opens a quiet period during which activations are ignored.
private var lastSeenSpaceIDs: [String: UInt64] = [:]
private var lastSpaceChangeAt: UInt64 = 0
private let quietAfterSpaceChange: UInt64 = 1_000_000_000

// Records the current Space of every display. True if any differs from the last one recorded.
@discardableResult
func noteCurrentSpace() -> Bool {
    let model = AppState.shared.displays
    model.reconcile()
    let seen = Dictionary(model.displays.map { ($0.uuid, $0.currentSpaceID) }, uniquingKeysWith: { a, _ in a })
    let changed = seen != lastSeenSpaceIDs
    lastSeenSpaceIDs = seen
    if changed { lastSpaceChangeAt = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }
    return changed
}

private func spaceChangedRecently() -> Bool {
    let changedNow = noteCurrentSpace()
    return changedNow || clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - lastSpaceChangeAt < quietAfterSpaceChange
}

func installActivationFollower() {
    noteCurrentSpace()
    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in noteCurrentSpace() }
    NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                      object: nil, queue: nil) { note in
        guard followEnabled, !spaceChangedRecently(),
              let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        followActivation(of: app.processIdentifier, name: app.localizedName ?? "?")
    }
}

// App.swift's status item and the dispatcher's `focus` still read the main display through these two.
// Remove them once those callers use DisplayModel.
func mainDisplay() -> DinkyDisplay? {
    let displays = dinky_displays()
    return displays.first { $0.displayID == CGMainDisplayID() } ?? displays.first
}

func currentSpaceIndex(_ main: DinkyDisplay) -> Int? {
    main.spaces.firstIndex { $0.spaceID == main.currentSpaceID }
}

/// Switches a display, the focused one by default, to a 0-based workspace index. False if nothing to do.
@discardableResult
func switchSpace(to workspace: Int, on display: Display? = nil, path: DinkySwitchPath = .mimi) -> Bool {
    let model = AppState.shared.displays
    model.reconcile()
    guard let display = display.flatMap({ d in model.displays.first { $0.uuid == d.uuid } }) ?? model.focusedDisplay(),
          display.workspaces.indices.contains(workspace) else { return false }
    return switchSpace(toSpaceID: display.workspaces[workspace], on: display, path: path)
}

/// Swipes the display to one of its Spaces, full-screen ones included. False if nothing to do.
@discardableResult
func switchSpace(toSpaceID target: UInt64, on display: Display, path: DinkySwitchPath = .mimi) -> Bool {
    guard let from = display.spaces.firstIndex(of: display.currentSpaceID),
          let to = display.spaces.firstIndex(of: target), from != to else { return false }
    let posted = dinky_switch_to_space_index(path, Int32(from + 1), Int32(to + 1), target, display.uuid as CFString)
    if posted {
        lastSeenSpaceIDs[display.uuid] = target
        lastSpaceChangeAt = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    }
    return posted
}

// Switches the display holding the app's frontmost window to that window's Space.
private func followActivation(of pid: pid_t, name: String) {
    let start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    let model = AppState.shared.displays
    // Front-to-back list of the app's normal windows on any Space; the first one is its frontmost.
    let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    var target: (space: UInt64, display: Display)?
    for w in info {
        guard w[kCGWindowOwnerPID as String] as? pid_t == pid,
              w[kCGWindowLayer as String] as? Int == 0,
              let wid = w[kCGWindowNumber as String] as? UInt32 else { continue }
        let sid = dinky_window_space_id(wid)
        guard let display = model.display(containingSpace: sid) else { continue }
        target = (sid, display)
        break
    }
    guard let target, target.space != target.display.currentSpaceID,
          switchSpace(toSpaceID: target.space, on: target.display) else { return }
    let spaces = target.display.spaces
    print(String(format: "activate %@: followed %d -> %d on display %u in %.1f ms", name,
                 (spaces.firstIndex(of: target.display.currentSpaceID) ?? -1) + 1, (spaces.firstIndex(of: target.space) ?? -1) + 1,
                 target.display.id, Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - start) / 1_000_000))
    fflush(stdout)
}
