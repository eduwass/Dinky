import AppKit
import DinkyPrivate

// Spike din-19v3: create Spaces through the bridged SLSBridgedSpaceCreateOperation.
func runSpaces(_ args: [String]) -> Int32 {
    switch args.first {
    case "ls":
        printSpaces()
        return 0
    case "create":
        return createSpace(Array(args.dropFirst()))
    default:
        fputs("usage: dinky spaces ls | create [--display <uuid>] [--restart-dock]\n", stderr)
        return 64
    }
}

private func printSpaces() {
    for display in dinky_displays() {
        let tag = display.displayID == CGMainDisplayID() ? " (main)" : ""
        print("\(display.uuid) id=\(display.displayID)\(tag)")
        for (i, space) in display.spaces.enumerated() {
            let current = space.spaceID == display.currentSpaceID ? "*" : " "
            let kind = space.isFullscreen ? "fullscreen" : space.isUser ? "user" : "type=\(space.type.rawValue)"
            print(" \(current)\(i + 1) space=\(space.spaceID) \(kind)")
        }
    }
}

// Creates one Space, then reports whether SkyLight's managed Space list shows it,
// and with --restart-dock whether it is still there after `killall Dock`.
private func createSpace(_ args: [String]) -> Int32 {
    let restartDock = args.contains("--restart-dock")
    let displays = dinky_displays()
    let display: DinkyDisplay?
    if let i = args.firstIndex(of: "--display"), i + 1 < args.count {
        display = displays.first { $0.uuid == args[i + 1] }
    } else {
        display = displays.first { $0.displayID == CGMainDisplayID() } ?? displays.first
    }
    guard let display else {
        fputs("spaces: display not found\n", stderr)
        return 1
    }

    let before = display.spaces.map(\.spaceID)
    print("display \(display.uuid): \(before.count) Spaces \(before)")

    let spaceID = dinky_create_space(display.uuid as CFString)
    guard spaceID != 0 else { return 1 }
    print("created space=\(spaceID)")

    let listed = waitFor(2000) { spaceIDs(display.uuid).contains(spaceID) }
    let after = spaceIDs(display.uuid)
    print("managed list \(listed ? "shows" : "does not show") it: \(after.count) Spaces \(after)")

    if restartDock {
        print("killall Dock")
        let dock = Process()
        dock.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        dock.arguments = ["Dock"]
        try? dock.run()
        dock.waitUntilExit()
        sleep(3)
        let survived = spaceIDs(display.uuid)
        print("after Dock restart: \(survived.contains(spaceID) ? "still there" : "gone"), \(survived.count) Spaces \(survived)")
    }
    return listed ? 0 : 1
}

private func spaceIDs(_ uuid: String) -> [UInt64] {
    dinky_displays().first { $0.uuid == uuid }?.spaces.map(\.spaceID) ?? []
}

private func waitFor(_ ms: Int, _ condition: () -> Bool) -> Bool {
    for _ in 0..<(ms / 10) {
        if condition() { return true }
        usleep(10_000)
    }
    return condition()
}
