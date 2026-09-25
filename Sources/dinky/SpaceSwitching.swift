import AppKit
import DinkyPrivate

// Switching the main display's Space with mimi's swipe, and following app activation (Cmd-Tab,
// Dock click) to the app's window's Space when the "switch to a Space with open windows" setting
// is off. Shared by the app and the dispatcher.

var followEnabled = true
// Arriving on a Space activates whatever is there (Finder on an empty one). Those activations must not
// be followed, or an empty Space bounces straight back to Finder's window. The Space-change notification
// is not reliable for swipes posted by other processes, so remember the last Space we saw instead: an
// activation that arrives after an unseen Space change is a consequence of that change, not a Cmd-Tab.
// Activation notifications can arrive a few hundred ms after the arrival, so a change noticed by the
// timer also opens a quiet period during which activations are ignored.
private var lastSeenSpaceID: UInt64 = 0
private var lastSpaceChangeAt: UInt64 = 0
private let quietAfterSpaceChange: UInt64 = 1_000_000_000

// Records the current Space. True if it differs from the last one recorded.
@discardableResult
func noteCurrentSpace() -> Bool {
    guard let main = mainDisplay() else { return false }
    let changed = main.currentSpaceID != lastSeenSpaceID
    lastSeenSpaceID = main.currentSpaceID
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

func mainDisplay() -> DinkyDisplay? {
    let displays = dinky_displays()
    return displays.first { $0.displayID == CGMainDisplayID() } ?? displays.first
}

// 0-based index of the current Space on the main display.
func currentSpaceIndex(_ main: DinkyDisplay) -> Int? {
    main.spaces.firstIndex { $0.spaceID == main.currentSpaceID }
}

// Switch the main display to a 0-based Space index with the given path. False if nothing to do.
@discardableResult
func switchSpace(to target: Int, path: DinkySwitchPath = .mimi) -> Bool {
    guard let main = mainDisplay(), let current = currentSpaceIndex(main),
          main.spaces.indices.contains(target), target != current else { return false }
    let posted = dinky_switch_to_space_index(path, Int32(current + 1), Int32(target + 1), main.spaces[target].spaceID, main.uuid as CFString)
    if posted {
        lastSeenSpaceID = main.spaces[target].spaceID
        lastSpaceChangeAt = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    }
    return posted
}

private func followActivation(of pid: pid_t, name: String) {
    let start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    guard let main = mainDisplay(), let current = currentSpaceIndex(main) else { return }
    // Front-to-back list of the app's normal windows on any Space; the first one is its frontmost.
    let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    var target: Int?
    for w in info {
        guard w[kCGWindowOwnerPID as String] as? pid_t == pid,
              w[kCGWindowLayer as String] as? Int == 0,
              let wid = w[kCGWindowNumber as String] as? UInt32 else { continue }
        let sid = dinky_window_space_id(wid)
        guard sid != 0, let index = main.spaces.firstIndex(where: { $0.spaceID == sid }) else { continue }
        target = index
        break
    }
    guard let target, target != current, switchSpace(to: target) else { return }
    print(String(format: "activate %@: followed %d -> %d in %.1f ms", name, current + 1, target + 1,
                 Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - start) / 1_000_000))
    fflush(stdout)
}
