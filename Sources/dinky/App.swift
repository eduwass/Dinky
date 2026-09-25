import AppKit
import DinkyPrivate

// `dinky app`: a menu bar item showing the current Space number, with commands as menu items, and the
// socket the CLI talks to.
func runApp(_ args: [String]) -> Int32 {
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

    func applicationDidFinishLaunching(_ note: Notification) {
        AppState.shared.loadConfig()
        socket = SocketServer(handle: Dispatcher.run)
        onboarding.run { [weak self] in self?.start() }
    }

    func applicationWillTerminate(_ note: Notification) {
        socket?.stop()
    }

    private func start() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self
        _ = AppState.shared.hotkeys.start()
        installActivationFollower()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refresh),
                                                          name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        // Fallback: our own swipes do not always produce the notification promptly.
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
        print("app: status item up, listening on \(socketPath)")
        fflush(stdout)
    }

    @objc private func refresh() {
        guard let main = mainDisplay(), let current = currentSpaceIndex(main) else {
            statusItem.button?.title = "?"
            return
        }
        AppState.shared.noteWorkspace(current)
        statusItem.button?.title = "\(current + 1)"
    }

    // Every action is a command string, run exactly as `dinky <command>` would run it.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let error = AppState.shared.configError {
            menu.addItem(withTitle: "Config error: \(error)", action: nil, keyEquivalent: "").isEnabled = false
            menu.addItem(.separator())
        }
        guard let main = mainDisplay(), let current = currentSpaceIndex(main) else {
            menu.addItem(withTitle: "No display", action: nil, keyEquivalent: "")
            return
        }
        let count = main.spaces.count
        menu.addItem(withTitle: "Workspace \(current + 1) of \(count)", action: nil, keyEquivalent: "")
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
        menu.addItem(item("Tile This Workspace", "layout tiles"))
        menu.addItem(.separator())
        let enabled = item("Enabled", "enable toggle")
        enabled.state = AppState.shared.enabled ? .on : .off
        menu.addItem(enabled)
        menu.addItem(item("Reload Config", "reload-config"))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit dinky", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.addItem(quit)
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

    @objc private func runCommand(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? String else { return }
        let reply = Dispatcher.run(command)
        if !reply.ok {
            fputs("\(command): \(reply.text)\n", stderr)
            NSSound.beep()
        }
    }
}
