import AppKit
import DinkyPrivate

func runSwitch(_ args: [String]) -> Int32 {
    var index: Int?
    var path = DinkySwitchPath.tuna
    var pathName = "tuna"
    var times = 1

    var i = 0
    while i < args.count {
        switch args[i] {
        case "--path":
            i += 1
            pathName = i < args.count ? args[i] : ""
            switch pathName {
            case "tuna": path = .tuna
            case "mimi": path = .mimi
            case "bridged": path = .bridged
            case "keys": path = .keys
            case "number": path = .number
            default:
                fputs("switch: --path must be tuna, mimi, bridged, keys or number\n", stderr)
                return 64
            }
        case "--times":
            i += 1
            guard i < args.count, let n = Int(args[i]), n > 0 else {
                fputs("switch: --times needs a positive number\n", stderr)
                return 64
            }
            times = n
        default:
            guard index == nil, let n = Int(args[i]) else {
                fputs("usage: dinky switch <space-index> [--path tuna|mimi|bridged|keys|number] [--times N]\n", stderr)
                return 64
            }
            index = n
        }
        i += 1
    }
    guard let index else {
        fputs("usage: dinky switch <space-index> [--path tuna|mimi|bridged|keys|number] [--times N]\n", stderr)
        return 64
    }

    let displays = dinky_displays()
    guard let main = displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? displays.first else {
        fputs("switch: no displays\n", stderr)
        return 1
    }
    let spaces = main.spaces.map { $0.spaceID }
    let uuid = main.uuid as CFString
    guard spaces.count >= 2 else {
        fputs("switch: main display has \(spaces.count) Space, need at least 2\n", stderr)
        return 1
    }
    guard let current = spaces.firstIndex(of: main.currentSpaceID) else {
        fputs("switch: current Space \(main.currentSpaceID) is not in the main display's list\n", stderr)
        return 1
    }
    guard dinky_current_space_id(uuid) == main.currentSpaceID else {
        fputs("switch: dinky_current_space_id(\(main.uuid)) disagrees with SLSCopyManagedDisplaySpaces\n", stderr)
        return 1
    }
    guard (1...spaces.count).contains(index) else {
        fputs("switch: space index \(index) out of range 1...\(spaces.count)\n", stderr)
        return 1
    }
    guard index - 1 != current else {
        fputs("switch: already on Space \(index)\n", stderr)
        return 1
    }

    // 0-based from here on.
    let a = current
    let b = index - 1
    var from = a
    var to = b
    var landed: [Double] = []
    var timeouts = 0

    for _ in 0..<times {
        let start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        guard dinky_switch_to_space_index(path, Int32(from + 1), Int32(to + 1), spaces[to], uuid) else {
            fputs("switch: \(pathName) failed to post\n", stderr)
            return 1
        }

        var observed = dinky_current_space_id(uuid)
        var now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        while observed != spaces[to] && now - start < 3_000_000_000 {
            usleep(500)
            observed = dinky_current_space_id(uuid)
            now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        }
        let ms = Double(now - start) / 1_000_000
        let observedIndex = spaces.firstIndex(of: observed)
        let ms1 = String(format: "%.1f", ms)

        if observed == spaces[to] {
            print("\(pathName) \(from + 1) -> \(to + 1) landed \(ms1) ms")
            landed.append(ms)
        } else {
            let at = observedIndex.map { String($0 + 1) } ?? "sid:\(observed)"
            print("\(pathName) \(from + 1) -> \(to + 1) timeout at \(at) \(ms1) ms")
            timeouts += 1
        }

        // Alternate from wherever we actually are.
        guard let here = observedIndex, here == a || here == b else {
            if times > 1 { fputs("switch: ended up off the two test Spaces, stopping\n", stderr) }
            break
        }
        from = here
        to = here == a ? b : a
    }

    if times > 1 {
        let sorted = landed.sorted()
        if sorted.isEmpty {
            print("summary: 0 landed, \(timeouts) timed out")
        } else {
            let median = sorted.count % 2 == 1
                ? sorted[sorted.count / 2]
                : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
            print(String(format: "summary: min %.1f median %.1f max %.1f ms, %d landed, %d timed out",
                         sorted.first!, median, sorted.last!, sorted.count, timeouts))
        }
    }
    return timeouts == 0 ? 0 : 1
}
