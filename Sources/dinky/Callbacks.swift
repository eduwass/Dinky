import Foundation

// The config's callbacks, named as in AeroSpace: `exec-on-workspace-change` when any display's current
// workspace changes (dinky's switches and native ones alike), `on-focus-changed` when the focused window
// changes, debounced, `on-mode-changed` when the binding mode changes, and `after-startup-command` once.
// Started once the coordinator has read the windows and displays, so startup fires nothing but
// `after-startup-command`. Main thread only.
final class Callbacks {
    /// The workspace number each display was last seen on, by UUID; "" off the numbered workspaces.
    private var workspaces: [String: String] = [:]
    private var pendingFocus: DispatchWorkItem?

    func start() {
        let state = AppState.shared
        for display in state.displays.displays { workspaces[display.uuid] = number(display) }
        state.displays.observe { [weak self] in self?.displaysChanged($0) }
        state.coordinator?.onFocusChange = { [weak self] in self?.focusChanged() }
        state.hotkeys.onModeChange = { _ in run(AppState.shared.config.onModeChanged) }
        run(state.config.afterStartupCommand)
    }

    private func displaysChanged(_ model: DisplayModel) {
        let argv = AppState.shared.config.execOnWorkspaceChange
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
            guard !argv.isEmpty else { continue }
            exec(argv, env: ["DINKY_FOCUSED_WORKSPACE": new, "DINKY_PREV_WORKSPACE": old, "DINKY_MONITOR_ID": "\(i + 1)",
                             "AEROSPACE_FOCUSED_WORKSPACE": new, "AEROSPACE_PREV_WORKSPACE": old])
        }
    }

    private func focusChanged() {
        pendingFocus?.cancel()
        let work = DispatchWorkItem { run(AppState.shared.config.onFocusChanged) }
        pendingFocus = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func number(_ display: Display) -> String {
        display.currentWorkspace.map { "\($0 + 1)" } ?? ""
    }
}

/// Runs dinky command strings through the dispatcher, logging failures.
private func run(_ commands: [String]) {
    for command in commands {
        let reply = Dispatcher.run(command)
        if !reply.ok { fputs("callback \(command): \(reply.text)\n", stderr) }
    }
}

/// Starts a process without waiting for it. Its output goes to dinky's own stdout and stderr, the log.
/// Homebrew's directories go first on PATH, as in AeroSpace, since apps started from Finder lack them.
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
