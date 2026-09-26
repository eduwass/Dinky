import AppKit
import DinkyPrivate
import Sparkle

// `dinky app`: a menu bar item showing the focused display's workspace number, with commands as menu
// items, and the socket the CLI talks to.
func runApp() -> Int32 {
    guard !appIsRunning() else {
        fputs("dinky: already running (\(socketPath))\n", stderr)
        return 1
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = DinkyApp()
    app.delegate = delegate
    app.run()
    return 0
}

final class DinkyApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var socket: SocketServer?
    private let onboarding = Onboarding()
    private var signals: [DispatchSourceSignal] = []
    // Only a bundle carries the feed URL; a bare debug binary would otherwise show an "Unable to Check
    // For Updates" alert at launch that blocks the socket until dismissed.
    private let updater = SPUStandardUpdaterController(startingUpdater: Bundle.main.infoDictionary?["SUFeedURL"] != nil,
                                                       updaterDelegate: nil, userDriverDelegate: nil)

    func applicationDidFinishLaunching(_ note: Notification) {
        AppState.shared.loadConfig()
        socket = SocketServer(handle: handleCommand)
        // `kill` and logout quit through NSApplication, so windows are restored on the way out.
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signals.append(source)
        }
        onboarding.run { [weak self] in self?.start() }
    }

    func applicationWillTerminate(_ note: Notification) {
        AppState.shared.quit()
        socket?.stop()
    }

    private func start() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self
        _ = AppState.shared.hotkeys.start()
        installActivationFollower()
        ensureWorkspaceCount()
        AppState.shared.startCoordinator()
        // After the display model's own subscription, so it has read the new Space.
        EventHub.shared.subscribe { [weak self] event in
            if event.kind == .spaceChange { self?.refresh() }
        }
        // Fallback: our own swipes do not always produce the notification promptly.
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
        print("app: status item up, listening on \(socketPath)")
        print("STATUS:READY")  // fut's run extension watches for this line
        fflush(stdout)
    }

    private func refresh() {
        let state = AppState.shared
        let workspace = state.displays.focusedDisplay()?.currentWorkspace
        statusItem.button?.title = (workspace.map { "\($0 + 1)" } ?? "?") + (state.configError == nil ? "" : "!")
        statusItem.button?.appearsDisabled = !state.enabled
    }

    // Every action is a command string, run exactly as `dinky <command>` would run it.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let state = AppState.shared
        let display = state.displays.focusedDisplay()
        let count = display?.workspaces.count ?? 0
        let current = display?.currentWorkspace
        menu.addItem(withTitle: "Space \(current.map { "\($0 + 1)" } ?? "?") of \(count)", action: nil, keyEquivalent: "")
        if let error = state.configError {
            menu.addItem(withTitle: "Config error: \(error)", action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())

        let go = NSMenu()
        let moveTo = NSMenu()
        let moveFollow = NSMenu()
        for i in 0..<count {
            let title = "Workspace \(i + 1)" + (i == current ? " (current)" : "")
            go.addItem(item(title, "workspace \(i + 1)", enabled: i != current))
            moveTo.addItem(item(title, "move-window-to-workspace \(i + 1)", enabled: i != current))
            moveFollow.addItem(item(title, "move-window-to-workspace \(i + 1) --follow", enabled: i != current))
        }
        menu.addItem(submenu("Go to Workspace", go))
        menu.addItem(submenu("Move Window to Workspace", moveTo))
        menu.addItem(submenu("Move Window and Follow", moveFollow))
        menu.addItem(item("Re-tile", "retile"))
        menu.addItem(item("Reload Config", "reload-config"))
        menu.addItem(.separator())
        let enabled = item("Enabled", "enable toggle")
        enabled.state = state.enabled ? .on : .off
        menu.addItem(enabled)
        let recoverable = state.recovery.recoverable
        if recoverable > 0 {
            menu.addItem(item("Restore \(recoverable) windows from the previous session", "recover"))
        }
        menu.addItem(.separator())
        let updates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)
        menu.addItem(NSMenuItem(title: "Quit dinky", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
    }

    private func item(_ title: String, _ command: String, enabled: Bool = true) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: #selector(runCommand(_:)), keyEquivalent: "")
        it.target = self
        it.representedObject = command
        it.toolTip = "dinky \(command)"
        it.isEnabled = enabled
        return it
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.submenu = menu
        return it
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        updater.checkForUpdates(sender)
    }

    @objc private func runCommand(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? String else { return }
        let reply = handleCommand(command)
        if !reply.ok {
            fputs("\(command): \(reply.text)\n", stderr)
            NSSound.beep()
        }
    }
}

/// A command from the menu or the CLI. `recover` belongs to the app rather than the command vocabulary.
private func handleCommand(_ line: String) -> Reply {
    line == "recover" ? AppState.shared.recover() : Dispatcher.run(line)
}
