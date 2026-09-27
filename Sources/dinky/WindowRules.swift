import AppKit
import DinkyCommands
import DinkyConfig

// Window classification for the coordinator: the AX window kind and the config's `[[rules]]`.

extension Coordinator {
    /// False for a window to tile, true for one to float, nil while its AX element is not there yet
    /// (a retry is scheduled; after a few, the window floats since dinky could not move it anyway).
    func classify(_ window: Window) -> Bool? {
        guard let element = axWindow(pid: window.pid, wid: window.id, timeout: FrameApplier.timeout) else {
            let tries = attempts[window.id, default: 0] + 1
            attempts[window.id] = tries
            guard tries < 5 else { return true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, let window = model.windows[window.id] else { return }
                track(window)
                flush()
            }
            return nil
        }
        attempts[window.id] = nil
        let kind = windowKind(subrole: axString(element, kAXSubroleAttribute))
        var resizable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &resizable)
        let title = axString(element, kAXTitleAttribute) ?? ""
        // `layout floating` and `layout tiling` decide here, the last one wins. Other rule commands, such as
        // move-window-to-workspace, run for this window once it is placed.
        var floats: Bool?
        for command in config.commands(for: window, kind: kind, title: title) {
            switch command {
            case .layout([.floating]): floats = true
            case .layout([.tiling]): floats = false
            default:
                DispatchQueue.main.async {
                    let reply = Dispatcher.run(command, window: window.id)
                    if !reply.ok { fputs("rule: \(reply.text)\n", stderr) }
                }
            }
        }
        return kind != .normal || !resizable.boolValue || floats == true
    }
}

extension Config {
    /// The commands of every rule that matches, in order. Commands that do not parse are skipped.
    func commands(for window: Window, kind: WindowKind, title: String) -> [Command] {
        rules.filter { $0.matches(appId: window.bundleID, appName: window.appName, title: title, kind: kind) }
            .flatMap { $0.run.compactMap { try? Command.parse($0) } }
    }
}

/// The rule kind for an AX subrole. Anything that is not a standard window, dialog or sheet is a panel.
private func windowKind(subrole: String?) -> WindowKind {
    switch subrole {
    case kAXStandardWindowSubrole: .normal
    case kAXDialogSubrole, kAXSystemDialogSubrole: .dialog
    case "AXSheet": .sheet
    default: .panel
    }
}

private func axString(_ element: AXUIElement, _ attribute: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value as? String
}

