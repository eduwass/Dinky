import AppKit
import DinkyPrivate

func runMove(_ args: [String]) -> Int32 {
    if args == ["--check"] {
        print("bridged dispatcher: \(dinky_bridged_dispatcher_available() ? "resolved" : "NOT FOUND")")
        print("SLSBridgedMoveWindowsToManagedSpaceOperation: \(NSClassFromString("SLSBridgedMoveWindowsToManagedSpaceOperation") != nil ? "present" : "MISSING")")
        return 0
    }

    let follow = args.contains("--follow")
    let positional = args.filter { $0 != "--follow" }
    guard positional.count == 2, let wid = UInt32(positional[0]), let index = Int(positional[1]) else {
        fputs("usage: dinky move <window-id> <space-index> [--follow] | --check\n", stderr)
        return 64
    }

    let displays = dinky_displays()
    guard let main = displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? displays.first else {
        fputs("move: no displays\n", stderr)
        return 1
    }
    guard index >= 1, index <= main.spaces.count else {
        fputs("move: space index \(index) out of range 1...\(main.spaces.count)\n", stderr)
        return 1
    }
    let target = main.spaces[index - 1].spaceID

    let from = dinky_window_space_id(wid)
    guard from != 0 else {
        fputs("move: window \(wid) has no Space\n", stderr)
        return 1
    }
    guard from != target else {
        fputs("move: window \(wid) is already on Space \(index)\n", stderr)
        return 1
    }
    let fromLabel = label(from, main)
    print("window \(wid) on Space \(fromLabel) (sid \(from)), moving to \(index) (sid \(target))")

    var ids = [wid]
    let start = DispatchTime.now()
    guard dinky_move_windows_to_space(&ids, 1, target) else {
        fputs("move: bridged move failed\n", stderr)
        return 1
    }

    var observed = from
    while ms(since: start) < 2000 {
        observed = dinky_window_space_id(wid)
        if observed == target { break }
        usleep(1000)
    }
    let elapsed = ms(since: start)
    if observed == target {
        print("window \(wid) \(fromLabel) -> \(index): landed in \(elapsed) ms")
    } else {
        print("window \(wid) \(fromLabel) -> \(index): timeout after \(elapsed) ms, observed Space \(label(observed, main)) (sid \(observed))")
        return 1
    }

    guard follow else { return 0 }

    let uuid = main.uuid as CFString
    let current = dinky_current_space_id(uuid)
    guard let currentIndex = main.spaces.firstIndex(where: { $0.spaceID == current }) else {
        fputs("move: current Space \(current) not on main display\n", stderr)
        return 1
    }
    let followStart = DispatchTime.now()
    guard dinky_switch_to_space_index(.mimi, Int32(currentIndex + 1), Int32(index), target, uuid) else {
        fputs("move: follow switch failed to post\n", stderr)
        return 1
    }
    var now = current
    while ms(since: followStart) < 3000 {
        now = dinky_current_space_id(uuid)
        if now == target { break }
        usleep(1000)
    }
    let followElapsed = ms(since: followStart)
    if now == target {
        print("follow: desktop followed \(currentIndex + 1) -> \(index) in \(followElapsed) ms")
        return 0
    }
    print("follow: desktop did not follow after \(followElapsed) ms, current Space \(label(now, main)) (sid \(now))")
    return 1
}

private func label(_ sid: UInt64, _ display: DinkyDisplay) -> String {
    if let i = display.spaces.firstIndex(where: { $0.spaceID == sid }) { return String(i + 1) }
    return sid == 0 ? "-" : "?"
}

private func ms(since start: DispatchTime) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
}
