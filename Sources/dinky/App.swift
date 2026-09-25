import AppKit
import DinkyPrivate

// `dinky app`: a menu bar item showing the current Space number, with the spike's actions as menu items.
func runApp(_ args: [String]) -> Int32 {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = DinkyApp()
    app.delegate = delegate
    app.run()
    return 0
}

final class DinkyApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let onboarding = Onboarding()

    func applicationDidFinishLaunching(_ note: Notification) {
        applyStartAtLogin()
        onboarding.run { [weak self] in self?.start() }
    }

    private func start() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self
        _ = installHotkeyTap()
        installActivationFollower()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refresh),
                                                          name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        // Fallback: our own swipes do not always produce the notification promptly.
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
        print("app: status item up")
        fflush(stdout)
    }

    @objc private func refresh() {
        guard let main = mainDisplay(), let current = currentSpaceIndex(main) else {
            statusItem.button?.title = "?"
            return
        }
        statusItem.button?.title = "\(current + 1)"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let main = mainDisplay(), let current = currentSpaceIndex(main) else {
            menu.addItem(withTitle: "No display", action: nil, keyEquivalent: "")
            return
        }
        let count = main.spaces.count
        menu.addItem(withTitle: "Space \(current + 1) of \(count)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        let go = NSMenu()
        let moveTo = NSMenu()
        let moveFollow = NSMenu()
        for i in 0..<count {
            let title = "Space \(i + 1)" + (i == current ? " (current)" : "")
            go.addItem(item(title, #selector(goToSpace(_:)), tag: i, enabled: i != current))
            moveTo.addItem(item(title, #selector(moveWindowToSpace(_:)), tag: i, enabled: i != current))
            moveFollow.addItem(item(title, #selector(moveWindowAndFollow(_:)), tag: i, enabled: i != current))
        }
        menu.addItem(submenu("Go to Space", go))
        menu.addItem(submenu("Move Window to Space", moveTo))
        menu.addItem(submenu("Move Window and Follow", moveFollow))
        menu.addItem(item("Tile This Space", #selector(tileSpace(_:))))
        menu.addItem(.separator())
        let hk = item("Ctrl-Arrow Switching", #selector(toggleHotkeys(_:)))
        hk.state = hotkeysEnabled ? .on : .off
        menu.addItem(hk)
        let fo = item("Follow Cmd-Tab to Window's Space", #selector(toggleFollow(_:)))
        fo.state = followEnabled ? .on : .off
        menu.addItem(fo)
        menu.addItem(.separator())
        menu.addItem(item("Quit dinky", #selector(quit(_:))))
    }

    private func item(_ title: String, _ action: Selector, tag: Int = 0, enabled: Bool = true) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
        it.target = self
        it.tag = tag
        it.isEnabled = enabled
        return it
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.submenu = menu
        return it
    }

    @objc private func goToSpace(_ sender: NSMenuItem) {
        switchSpace(to: sender.tag)
    }

    @objc private func moveWindowToSpace(_ sender: NSMenuItem) {
        moveFrontWindow(to: sender.tag, follow: false)
    }

    @objc private func moveWindowAndFollow(_ sender: NSMenuItem) {
        moveFrontWindow(to: sender.tag, follow: true)
    }

    private func moveFrontWindow(to target: Int, follow: Bool) {
        guard let main = mainDisplay(), main.spaces.indices.contains(target) else { return }
        let wid = frontWindowID()
        guard wid != 0 else { NSSound.beep(); return }
        var ids = [wid]
        guard dinky_move_windows_to_space(&ids, 1, main.spaces[target].spaceID) else { NSSound.beep(); return }
        if follow { switchSpace(to: target) }
    }

    @objc private func tileSpace(_ sender: NSMenuItem) {
        _ = runTile([])
    }

    @objc private func toggleHotkeys(_ sender: NSMenuItem) { hotkeysEnabled.toggle() }
    @objc private func toggleFollow(_ sender: NSMenuItem) { followEnabled.toggle() }
    @objc private func quit(_ sender: NSMenuItem) { NSApp.terminate(nil) }
}
