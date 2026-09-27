import Foundation

// The config's `[hooks]`: `workspace-changed` when any display's current workspace changes (dinky's switches
// and native ones alike), `focus-changed` when the focused window changes, debounced, `mode-changed` when
// the binding mode changes, and `startup` once. Started once the coordinator has read the windows and
// displays, so startup fires nothing but `startup`. Main thread only.
final class Hooks {
    /// The workspace number each display was last seen on, by UUID; "" off the numbered workspaces.
    private var workspaces: [String: String] = [:]
    private var pendingFocus: DispatchWorkItem?

    func start() {
        let state = AppState.shared
        for display in state.displays.displays { workspaces[display.uuid] = number(display) }
        state.displays.observe { [weak self] in self?.displaysChanged($0) }
        state.coordinator?.onFocusChange = { [weak self] in self?.focusChanged() }
        state.hotkeys.onModeChange = { _ in run(AppState.shared.config.hooks.modeChanged) }
        run(state.config.hooks.startup)
    }

    private func displaysChanged(_ model: DisplayModel) {
        let commands = AppState.shared.config.hooks.workspaceChanged
        for (i, display) in model.displays.enumerated() {
            let new = number(display)
            // A display that just appeared has not switched.
            guard let old = workspaces[display.uuid] else {
                workspaces[display.uuid] = new
                continue
            }
            guard old != new else { continue }
            // dinky's swipe passes through the Spaces in between; report only where it lands.
            if let target = SpaceSwitcher.shared.target(on: display.uuid), target != display.currentSpaceID { continue }
            workspaces[display.uuid] = new
            run(commands, env: ["DINKY_WORKSPACE": new, "DINKY_PREV_WORKSPACE": old, "DINKY_DISPLAY": "\(i + 1)"])
        }
    }

    private func focusChanged() {
        pendingFocus?.cancel()
        let work = DispatchWorkItem { run(AppState.shared.config.hooks.focusChanged) }
        pendingFocus = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func number(_ display: Display) -> String {
        display.currentWorkspace.map { "\($0 + 1)" } ?? ""
    }
}

/// Runs dinky command strings through the dispatcher, logging failures. `env` reaches `exec-and-forget`.
private func run(_ commands: [String], env: [String: String] = [:]) {
    for command in commands {
        let reply = Dispatcher.run(command, env: env)
        if !reply.ok { fputs("hook \(command): \(reply.text)\n", stderr) }
    }
}

/// Starts a process without waiting for it. Its output goes to dinky's own stdout and stderr, the log.
/// Homebrew's directories go first on PATH, since apps started from Finder lack them.
func exec(_ argv: [String], env: [String: String] = [:]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: argv[0])
    process.arguments = Array(argv.dropFirst())
    var environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new }
    environment["PATH"] = "/opt/homebrew/bin:/opt/homebrew/sbin:" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
    process.environment = environment
    process.standardInput = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        fputs("exec \(argv[0]): \(error.localizedDescription)\n", stderr)
    }
}
