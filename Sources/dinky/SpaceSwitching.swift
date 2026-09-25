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

/// Swipes the display to one of its Spaces, full-screen ones included. False if it is already there.
/// Returns once the swipe is posted; `SpaceSwitcher` confirms it and coalesces rapid requests.
@discardableResult
func switchSpace(toSpaceID target: UInt64, on display: Display) -> Bool {
    SpaceSwitcher.shared.request(target, on: display.uuid)
}

/// The Space the display is on, or is switching to while a switch is in flight.
func targetSpaceID(on display: Display) -> UInt64 {
    SpaceSwitcher.shared.target(on: display.uuid) ?? display.currentSpaceID
}

// Tells the activation follower that this Space change is ours, so the activation it causes is not followed.
func noteOwnSwitch(to target: UInt64, on uuid: String) {
    lastSeenSpaceIDs[uuid] = target
    lastSpaceChangeAt = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
}

// Switches to the Space of the app's frontmost window, unless the app has a window on the focused display's
// current Space: then Cmd-Tab stays put and the app's window here comes forward.
private func followActivation(of pid: pid_t, name: String) {
    let start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    let model = AppState.shared.displays
    let here = model.focusedDisplay()?.currentSpaceID
    // Front-to-back list of the app's normal windows on any Space; the first one is its frontmost.
    let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    var target: (space: UInt64, display: Display)?
    for w in info {
        guard w[kCGWindowOwnerPID as String] as? pid_t == pid,
              w[kCGWindowLayer as String] as? Int == 0,
              let wid = w[kCGWindowNumber as String] as? UInt32 else { continue }
        let sid = dinky_window_space_id(wid)
        if sid == here { return }
        guard target == nil, let display = model.display(containingSpace: sid) else { continue }
        target = (sid, display)
    }
    guard let target, target.space != target.display.currentSpaceID,
          switchSpace(toSpaceID: target.space, on: target.display) else { return }
    let spaces = target.display.spaces
    print(String(format: "activate %@: followed %d -> %d on display %u in %.1f ms", name,
                 (spaces.firstIndex(of: target.display.currentSpaceID) ?? -1) + 1, (spaces.firstIndex(of: target.space) ?? -1) + 1,
                 target.display.id, Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - start) / 1_000_000))
    fflush(stdout)
}

// One switch in flight per display. A request while one is in flight only replaces its target: once the
// posted swipe lands, the display goes on to the newest target from wherever it is, so a burst of requests
// never replays obsolete swipes. Landing is observed with `dinky_current_space_id`, not assumed; a swipe
// that has not landed after `timeout` is posted once more, then reported and dropped.
final class SpaceSwitcher {
    static let shared = SpaceSwitcher()

    private struct Flight {
        var target: UInt64      // the newest request
        var posted: UInt64 = 0  // what the last swipe went for
        var postedAt: UInt64 = 0
        var retried = false
        let startedAt = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    }

    private var flights: [String: Flight] = [:]
    private var timer: Timer?
    // The mimi path pumps the run loop between steps; the poll and new requests must not post meanwhile.
    private var posting = false
    private let timeout: UInt64 = 1_000_000_000

    func target(on uuid: String) -> UInt64? { flights[uuid]?.target }

    func request(_ target: UInt64, on uuid: String) -> Bool {
        if flights[uuid] != nil {
            flights[uuid]!.target = target
            flights[uuid]!.retried = false
            return true
        }
        guard dinky_current_space_id(uuid as CFString) != target else { return false }
        flights[uuid] = Flight(target: target)
        if !posting { post(on: uuid) }
        startPolling()
        return true
    }

    /// Posts a swipe from the display's observed Space to the flight's target. Drops the flight if it can't.
    private func post(on uuid: String) {
        guard var flight = flights[uuid] else { return }
        let spaces = dinky_displays().first { $0.uuid == uuid }?.spaces.map(\.spaceID) ?? []
        let current = dinky_current_space_id(uuid as CFString)
        guard let from = spaces.firstIndex(of: current), let to = spaces.firstIndex(of: flight.target) else {
            return finish(uuid, "switch: Space \(flight.target) is not on display \(uuid)")
        }
        flight.posted = flight.target
        flight.postedAt = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        flights[uuid] = flight
        noteOwnSwitch(to: flight.target, on: uuid)
        posting = true
        let ok = dinky_switch_to_space_index(Int32(from + 1), Int32(to + 1), uuid as CFString)
        posting = false
        if !ok { finish(uuid, "switch: posting the swipe to Space \(to + 1) failed") }
    }

    private func poll() {
        guard !posting else { return }
        for (uuid, flight) in flights {
            let observed = dinky_current_space_id(uuid as CFString)
            let ms = Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - flight.startedAt) / 1_000_000
            if flight.posted == 0 {
                post(on: uuid)  // requested while another display's swipe was being posted
            } else if observed == flight.posted, observed == flight.target {
                finish(uuid, String(format: "switch: landed on Space %llu in %.0f ms", observed, ms))
            } else if observed == flight.posted {
                post(on: uuid)  // landed on an older request; go on to the newest
            } else if clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - flight.postedAt > timeout {
                // The posted swipe did not land. Waiting for it first means it can't land late, after this.
                if observed == flight.target {
                    finish(uuid, String(format: "switch: on Space %llu after %.0f ms", observed, ms))
                } else if flight.retried {
                    finish(uuid, "switch: gave up on Space \(flight.target), display is on Space \(observed)", error: true)
                } else {
                    flights[uuid]!.retried = true
                    post(on: uuid)
                }
            }
        }
        if flights.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }

    private func finish(_ uuid: String, _ message: String, error: Bool = false) {
        flights[uuid] = nil
        if error { fputs(message + "\n", stderr) } else { print(message) }
        fflush(stdout)
    }

    private func startPolling() {
        guard timer == nil, !flights.isEmpty else { return }
        let timer = Timer(timeInterval: 0.01, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
